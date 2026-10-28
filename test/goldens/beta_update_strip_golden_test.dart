import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update_indicator.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

void main() {
  setUpAll(_loadFonts);

  testWidgets('available Beta patch adds the Sakura update notice', (
    tester,
  ) async {
    const goldenRoot = ValueKey<String>('beta-update-strip-golden-root');
    configureApplicationTestSurface(
      tester,
      const Size(1200, 836),
      disableAnimations: false,
    );
    const service = _GoldenUpdateService();
    final controller = BetaUpdateController(
      service: service,
      source: r'C:\private-beta-feed',
    );

    try {
      await controller.checkOnce();
      final theme = SakuraNightGardenSpec.theme.materialTheme();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
            primaryTextTheme: theme.primaryTextTheme.apply(
              fontFamily: 'Roboto',
            ),
          ),
          home: ThemeSpecScope(
            spec: SakuraNightGardenSpec.theme,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: RepaintBoundary(
                key: goldenRoot,
                child: BetaUpdateIndicator(
                  controller: controller,
                  onUpdateNow: () async {},
                ),
              ),
            ),
          ),
        ),
      );
      for (var index = 0; index < 44; index++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      await expectLater(
        find.byKey(goldenRoot),
        matchesGoldenFile('beta_update_notice_sakura_available_1200x836.png'),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      controller.dispose();
    }
  });
}

Future<void> _loadFonts() async {
  final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
        '${sdk.path}/bin/cache/artifacts/material_fonts',
      ).existsSync() &&
      sdk.parent.path != sdk.path) {
    sdk = sdk.parent;
  }
  for (final entry in <String, List<String>>{
    'Segoe UI': [
      '$windows/Fonts/segoeui.ttf',
      '$windows/Fonts/seguisb.ttf',
      '$windows/Fonts/segoeuib.ttf',
    ],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      final file = File(path);
      if (!file.existsSync()) continue;
      loader.addFont(
        file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  }
}

class _GoldenUpdateService implements BetaUpdateService {
  const _GoldenUpdateService();

  static const available = BetaUpdateSnapshot(
    phase: BetaUpdatePhase.available,
    currentVersion: '0.1.0-beta.5',
    targetVersion: '0.1.0-beta.6',
    sizeBytes: 2610822,
    fullSizeBytes: 66854193,
    deltaCount: 1,
  );

  @override
  Stream<BetaUpdateSnapshot> get snapshots =>
      const Stream<BetaUpdateSnapshot>.empty();

  @override
  Future<BetaUpdateSnapshot> currentStatus() async => available;

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async => available;

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async => available;

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async => available;

  @override
  Future<void> dispose() async {}
}
