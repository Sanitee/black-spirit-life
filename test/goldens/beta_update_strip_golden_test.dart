import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

void main() {
  testWidgets('available Beta patch adds a compact bottom status strip', (
    tester,
  ) async {
    const goldenRoot = ValueKey<String>('beta-update-strip-golden-root');
    configureApplicationTestSurface(tester, const Size(1200, 796));
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    const service = _GoldenUpdateService();

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: goldenRoot,
          child: BdoCraftPlannerApp(
            applicationFuture: Future.value(harness.bundle),
            marketGateway: const EmptyMarketGateway(),
            updateService: service,
            updateSource: r'C:\private-beta-feed',
            enableBetaUpdates: true,
          ),
        ),
      );
      for (var index = 0; index < 18; index++) {
        await tester.pump(const Duration(milliseconds: 80));
      }

      await expectLater(
        find.byKey(goldenRoot),
        matchesGoldenFile('beta_update_strip_available_1200x796.png'),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(harness.dispose);
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
