import 'dart:io';

import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'real packaged Journal assets pass install preparation without a host',
    () async {
      const override = String.fromEnvironment('FISH_PAYLOAD_ROOT');
      final bundled = Directory(
        'packages/bdo_fishing_core/assets/fish_companion',
      );
      final payload = Directory(
        override.isEmpty
            ? (bundled.existsSync() ? bundled.path : 'assets/fish_companion')
            : override,
      ).absolute;
      final build = Directory('build').absolute;
      await build.create(recursive: true);
      final scratch = await build.createTemp('journal-silver-check-');
      addTearDown(() async {
        expect(scratch.parent.path, build.path);
        await scratch.delete(recursive: true);
      });
      final personal = Directory('${scratch.path}/personal');
      final cache = Directory('${scratch.path}/cache');
      final webview = Directory('${scratch.path}/webview');
      final runtime = FishCompanionRuntime(
        personalDataRoot: personal,
        referenceCacheRoot: cache,
        webViewDataRoot: webview,
        packagedPayloadRoot: payload,
        managedProcessStarter: (_, _, {required workingDirectory}) async {
          fail('Install verification must not launch a host');
        },
      );
      expect((await runtime.install()).path, payload.path);
      expect(
        await File('${payload.path}/static/silver.webp').length(),
        greaterThan(0),
      );
      expect(await personal.exists(), isFalse);
      expect(await cache.exists(), isFalse);
      expect(await webview.exists(), isFalse);
    },
  );
}
