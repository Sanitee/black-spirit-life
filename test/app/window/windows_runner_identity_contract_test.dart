import 'dart:io';

import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner is locked to the public application identity', () {
    expect(AppIdentity.productName, 'Black Spirit Life');
    expect(AppIdentity.displayName, 'Black Spirit Life');
    expect(AppIdentity.applicationVersion, '0.1.3');
    expect(AppIdentity.inProcessBetaUpdatesEnabled, isFalse);
    expect(AppIdentity.outOfProcessBetaUpdatesEnabled, isTrue);
    expect(AppIdentity.releaseChannel, 'win-x64-stable');
    expect(AppIdentity.installerPackageId, 'BlackSpiritLife.App');
    expect(AppIdentity.stateDirectoryName, 'Black Spirit Life');
    expect(AppIdentity.localCacheDirectoryName, 'Black Spirit Life');
    expect(AppIdentity.windowsExecutableName, 'BlackSpiritLife.exe');
    expect(AppIdentity.windowsUpdaterHelperName, 'BlackSpiritLifeUpdater.exe');
    expect(
      AppIdentity.installerPackageId,
      isNot(AppIdentity.localCacheDirectoryName),
    );

    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    final runner = File('windows/runner/main.cpp').readAsStringSync();
    final resources = File('windows/runner/Runner.rc').readAsStringSync();

    expect(cmake, contains('project(black_spirit_life LANGUAGES CXX)'));
    expect(cmake, contains('set(BINARY_NAME "BlackSpiritLife")'));
    expect(runner, contains('L"${AppIdentity.displayName}"'));
    expect(
      resources,
      contains('VALUE "ProductName", "${AppIdentity.productName}"'),
    );
    expect(
      resources,
      contains(
        'VALUE "OriginalFilename", "${AppIdentity.windowsExecutableName}"',
      ),
    );
  });

  test('Windows icon contains every required shell size', () {
    final bytes = File(
      'windows/runner/resources/app_icon.ico',
    ).readAsBytesSync();
    expect(bytes.length, greaterThan(6));
    expect(bytes[0], 0);
    expect(bytes[1], 0);
    expect(bytes[2], 1);
    expect(bytes[3], 0);
    final count = bytes[4] | (bytes[5] << 8);
    expect(count, 7);
    final sizes = <int>{};
    for (var index = 0; index < count; index++) {
      final offset = 6 + index * 16;
      final width = bytes[offset] == 0 ? 256 : bytes[offset];
      final height = bytes[offset + 1] == 0 ? 256 : bytes[offset + 1];
      expect(height, width);
      expect(bytes[offset + 2], 0);
      expect(bytes[offset + 3], 0);
      sizes.add(width);
    }
    expect(sizes, <int>{16, 24, 32, 48, 64, 128, 256});
  });
}
