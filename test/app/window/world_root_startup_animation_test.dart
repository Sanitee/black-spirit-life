import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/window/world_root_startup_animation.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/visual/components/retained_asset_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  testWidgets('World-root cue enters once and settles into a gentle breath', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: WorldRootStartupAnimation())),
    );

    final state = tester.state<WorldRootStartupAnimationState>(
      find.byType(WorldRootStartupAnimation),
    );
    expect(state.debugProgress, 0);
    expect(state.debugIsAnimating, isTrue);
    final image = tester.widget<Image>(
      find.byKey(WorldRootStartupAnimation.artworkKey),
    );
    expect((image.image as AssetImage).assetName, AppIdentity.appIconAssetPath);

    await tester.pump(const Duration(milliseconds: 551));
    expect(state.debugProgress, inExclusiveRange(0, 1));
    expect(state.debugIsAnimating, isTrue);
    expect(
      tester
          .widget<Opacity>(find.byKey(WorldRootStartupAnimation.sheenKey))
          .opacity,
      greaterThan(0),
    );

    await tester.pump(const Duration(milliseconds: 550));
    expect(state.debugProgress, 1);
    expect(state.debugIsAnimating, isTrue);
    expect(state.debugIsBreathing, isTrue);
    expect(
      tester
          .widget<Opacity>(find.byKey(WorldRootStartupAnimation.sheenKey))
          .opacity,
      0,
    );
    expect(
      tester
          .widget<Opacity>(find.byKey(WorldRootStartupAnimation.glowKey))
          .opacity,
      closeTo(.18, .0001),
    );

    await tester.pump(const Duration(milliseconds: 550));
    expect(state.debugProgress, 1);
    expect(state.debugBreathingProgress, inExclusiveRange(0, 1));
    expect(state.debugIsAnimating, isTrue);
    expect(
      tester
          .widget<Opacity>(find.byKey(WorldRootStartupAnimation.glowKey))
          .opacity,
      greaterThan(.18),
    );
  });

  testWidgets('reduced motion renders the final emblem immediately', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      const MaterialApp(home: Center(child: WorldRootStartupAnimation())),
    );

    final state = tester.state<WorldRootStartupAnimationState>(
      find.byType(WorldRootStartupAnimation),
    );
    expect(state.debugProgress, 1);
    expect(state.debugBreathingProgress, 0);
    expect(state.debugIsBreathing, isFalse);
    expect(state.debugIsAnimating, isFalse);
    expect(
      tester
          .widget<Opacity>(find.byKey(WorldRootStartupAnimation.sheenKey))
          .opacity,
      0,
    );
    expect(find.byKey(WorldRootStartupAnimation.artworkKey), findsOneWidget);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: false);
    await tester.pump();
    expect(state.debugProgress, 1, reason: 'reduced motion never replays');
    expect(state.debugIsAnimating, isFalse);
  });

  testWidgets('missing World-root artwork stays visibly explicit', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: WorldRootStartupAnimation(
            assetPath: 'assets/app/missing-world-root.png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(WorldRootStartupAnimation.artworkFailureKey),
      findsOneWidget,
    );
    expect(find.byType(RetainedAssetFailure), findsOneWidget);
    expect(find.text('Artwork unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bootstrap failure replaces a running cue without delay', (
    tester,
  ) async {
    final pending = Completer<ApplicationBundle>();
    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: pending.future),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WorldRootStartupAnimation), findsOneWidget);

    pending.completeError(StateError('bootstrap stopped'));
    await tester.pump();

    expect(find.byType(WorldRootStartupAnimation), findsNothing);
    expect(find.textContaining('bootstrap stopped'), findsOneWidget);
  });

  testWidgets('a ready planner replaces a running cue without splash delay', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
    final pending = Completer<ApplicationBundle>();
    await tester.pumpWidget(
      BdoCraftPlannerApp(
        applicationFuture: pending.future,
        marketGateway: const EmptyMarketGateway(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WorldRootStartupAnimation), findsOneWidget);

    pending.complete(harness.bundle);
    await tester.pump();
    await tester.pump();

    expect(find.byType(WorldRootStartupAnimation), findsNothing);
    expect(find.byType(PlannerView), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });
}
