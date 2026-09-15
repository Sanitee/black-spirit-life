import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'application_bootstrap.dart';
import 'window/window_host_service.dart';

void runBdoCraftPlanner() {
  WidgetsFlutterBinding.ensureInitialized();
  installStartupWindowCloseHandler();
  FlutterError.onError = FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught application error: $error\n$stack');
    return true;
  };
  runZonedGuarded(() {
    final applicationDirectory = Completer<Directory>();
    final applicationFuture = const ApplicationBootstrapService().load(
      onApplicationDirectoryResolved: (directory) {
        if (!applicationDirectory.isCompleted) {
          applicationDirectory.complete(directory);
        }
      },
    );
    unawaited(
      applicationFuture.then<void>(
        (bundle) {
          if (!applicationDirectory.isCompleted) {
            applicationDirectory.complete(
              bundle.stateRepository.paths.applicationDirectory,
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!applicationDirectory.isCompleted) {
            applicationDirectory.completeError(error, stackTrace);
          }
        },
      ),
    );
    final fishCompanionRuntimeHost = createApplicationFishCompanionRuntimeHost(
      applicationDirectory: () => applicationDirectory.future,
    );
    // Loading, migration, and first-run setup all mount Fish Map offstage so
    // it is ready when selected. Replace the initial no-op close handler
    // before that prewarm begins: Windows must not destroy Flutter's binary
    // messenger while the native Fish surface is being created or disposed.
    installStartupWindowCloseHandler(
      beforeClose: fishCompanionRuntimeHost.freezeAndFlushForApplicationExit,
    );
    unawaited(fishCompanionRuntimeHost.prewarm());
    runApp(
      BdoCraftPlannerApp(
        applicationFuture: applicationFuture,
        fishCompanionRuntimeHost: fishCompanionRuntimeHost,
      ),
    );
  }, (error, stack) => debugPrint('Uncaught zone error: $error\n$stack'));
}

/// Allows Windows close requests while the application is still loading,
/// showing a startup failure, or collecting first-run choices. The full
/// workspace replaces this handler with its durable save-before-close barrier
/// as soon as the full planner workspace mounts.
void installStartupWindowCloseHandler({
  WindowHostService windowHost = const WindowHostService(),
  Future<void> Function()? beforeClose,
}) {
  windowHost.installCloseRequestHandler(beforeClose ?? () async {});
}
