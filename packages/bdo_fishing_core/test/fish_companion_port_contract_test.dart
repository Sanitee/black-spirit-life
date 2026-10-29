import 'dart:io';

import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Stable Fish service and native navigation use the same port range', () {
    expect(fishCompanionFirstPort, 8765);
    expect(fishCompanionLastPort, 8795);
    // Flutter tests may run from the package or the application root.
    final native = <File>[
      File('../webview_flutter_windows/windows/video_navigation_policy.h'),
      File(
        'packages/webview_flutter_windows/windows/video_navigation_policy.h',
      ),
    ].firstWhere((file) => file.existsSync());
    final source = native.readAsStringSync();
    int nativePort(String name) =>
        int.parse(RegExp('$name = ([0-9]+);').firstMatch(source)!.group(1)!);
    expect(nativePort('kFishCompanionFirstPort'), fishCompanionFirstPort);
    expect(nativePort('kFishCompanionLastPort'), fishCompanionLastPort);
  });
}
