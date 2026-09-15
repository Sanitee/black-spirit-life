import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update_indicator.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

void main() {
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
      await tester.pumpWidget(
        MaterialApp(
          theme: SakuraNightGardenSpec.theme.materialTheme(),
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
