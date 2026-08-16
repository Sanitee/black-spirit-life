import 'dart:async';

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
  runZonedGuarded(
    () => runApp(
      BdoCraftPlannerApp(
        applicationFuture: const ApplicationBootstrapService().load(),
      ),
    ),
    (error, stack) => debugPrint('Uncaught zone error: $error\n$stack'),
  );
}

/// Allows Windows close requests while the application is still loading,
/// showing a startup failure, or collecting first-run choices. The full
/// workspace replaces this handler with its durable save-before-close barrier
/// as soon as the full planner workspace mounts.
void installStartupWindowCloseHandler({
  WindowHostService windowHost = const WindowHostService(),
}) {
  windowHost.installCloseRequestHandler(() async {});
}
