import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'freezing cancels a startup waiting for the application directory',
    () async {
      final applicationDirectory = Completer<Directory>();
      var starterCalled = false;
      final host = createApplicationFishCompanionRuntimeHost(
        applicationDirectory: () => applicationDirectory.future,
        referenceCacheDirectory: Directory('unused-reference-cache'),
        starter: (_) async {
          starterCalled = true;
          return _FakeFishCompanionServiceHandle();
        },
      );

      final readyFailure = expectLater(
        host.ready(),
        throwsA(isA<FishCompanionStartupCanceled>()),
      );
      await host.freezeAndFlush().timeout(const Duration(seconds: 1));

      await readyFailure;
      expect(starterCalled, isFalse);
      await host.shutdown();
    },
  );
}

final class _FakeFishCompanionServiceHandle
    implements FishCompanionServiceHandle {
  @override
  final Directory root = Directory('unused-service-root');

  @override
  final Directory personalDataRoot = Directory('unused-personal-root');

  @override
  final Directory webViewDataRoot = Directory('unused-personal-root/webview2');

  @override
  final Uri uri = Uri.parse('http://127.0.0.1:18765/');

  @override
  Future<void> checkpoint() async {}

  @override
  Future<void> shutdown() async {}

  @override
  void dispose() {}
}
