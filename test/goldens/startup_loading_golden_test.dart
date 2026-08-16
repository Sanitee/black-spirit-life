import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/window/world_root_startup_animation.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

void main() {
  testWidgets('startup loading keeps a restrained animated hierarchy', (
    tester,
  ) async {
    const goldenRoot = ValueKey<String>('startup-loading-golden-root');
    configureApplicationTestSurface(tester, const Size(1200, 752));
    final pending = Completer<ApplicationBundle>();

    await tester.pumpWidget(
      RepaintBoundary(
        key: goldenRoot,
        child: BdoCraftPlannerApp(applicationFuture: pending.future),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(AppIdentity.appIconAssetPath),
        tester.element(find.byType(WorldRootStartupAnimation)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 550));

    await expectLater(
      find.byKey(goldenRoot),
      matchesGoldenFile('startup_loading_breathing_1200x752.png'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
