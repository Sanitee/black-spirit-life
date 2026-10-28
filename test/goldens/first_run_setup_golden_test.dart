import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_botanical_assets.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

void main() {
  testWidgets('first-run setup hierarchy and saved-location notice', (
    tester,
  ) async {
    const goldenRoot = ValueKey<String>('first-run-setup-golden-root');
    const assetPrecacheHost = ValueKey<String>(
      'first-run-setup-asset-precache-host',
    );
    configureApplicationTestSurface(tester, const Size(1200, 752));
    var harness = (await tester.runAsync(
      () => ApplicationTestHarness.create(setupCompleted: false),
    ))!;
    await tester.runAsync(harness.disposeControllerOnly);
    harness = harness.rebindControllerInCurrentZone();
    final applicationFuture = Future.value(harness.bundle);

    try {
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox(key: assetPrecacheHost)),
      );
      final context = tester.element(find.byKey(assetPrecacheHost));
      for (final assetPath in const <String>[
        AppIdentity.appIconAssetPath,
        SakuraNightGardenSpec.blackenedCedarAssetPath,
        SakuraBotanicalAssets.titleSprig,
        SakuraBotanicalAssets.sectionBloom,
      ]) {
        await tester.runAsync(
          () => precacheImage(AssetImage(assetPath), context),
        );
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: goldenRoot,
          child: BdoCraftPlannerApp(
            enableOpportunityAutoCheck: false,
            applicationFuture: applicationFuture,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mastery'), findsOneWidget);

      await expectLater(
        find.byKey(goldenRoot),
        matchesGoldenFile('first_run_setup_mastery_1200x752.png'),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('setup-section-afkLoad')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Feathery Steps'), findsOneWidget);
      await expectLater(
        find.byKey(goldenRoot),
        matchesGoldenFile('first_run_setup_afk_1200x752.png'),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('setup-section-marketSales')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Family Fame bonus'), findsOneWidget);
      await expectLater(
        find.byKey(goldenRoot),
        matchesGoldenFile('first_run_setup_market_1200x752.png'),
      );

      await tester.tap(find.byKey(const ValueKey<String>('setup-value-pack')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('first-run-setup-finish')),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(goldenRoot),
        matchesGoldenFile('first_run_setup_notice_1200x752.png'),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('first-run-setup-location-okay')),
      );
      await tester.pumpAndSettle();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(harness.dispose);
    }
  });
}
