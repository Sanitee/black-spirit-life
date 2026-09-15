import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_completion_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

const _intermediate = 'Intermediate Reagent';
const _feedback = ValueKey('planner-completion-feedback:$_intermediate');

void main() {
  testWidgets('completion commits once immediately, then safely fades away', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final step = harness.controller.active.plan.value.steps.first;
    final complete = find.byKey(PlannerActionKeys.row('P08', step.name));
    await tester.tap(complete);
    for (final mode in CraftMode.values) {
      expect(
        harness.controller.modes[mode]!.state.value.inventory[step.name],
        step.produced,
      );
    }
    final inventory = Map.of(harness.controller.active.state.value.inventory);
    // A second activation in the same frame cannot repeat the transaction.
    await tester.tap(complete);
    expect(harness.controller.active.state.value.inventory, inventory);
    await tester.pump();
    final feedback = find.byKey(_feedback);
    expect(feedback, findsOneWidget);
    expect(tester.widget<IgnorePointer>(feedback).ignoring, isTrue);
    final done = tester.widget<AppCompletionControl>(
      find.descendant(
        of: feedback,
        matching: find.byType(AppCompletionControl),
      ),
    );
    expect(done.completed, isTrue);
    expect(done.onPressed, isNull);
    final height = tester.getSize(feedback).height;
    await tester.tap(complete, warnIfMissed: false);
    expect(harness.controller.active.state.value.inventory, inventory);
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getSize(feedback).height, height);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getSize(feedback).height, lessThan(height));
    expect(tester.getSize(feedback).height, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 60));
    expect(feedback, findsNothing);
    expect(harness.controller.active.state.value.inventory, inventory);
    await _dispose(tester, harness);
  });

  testWidgets('reduced motion removes completion immediately', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final harness = await _mount(tester);
    await tester.tap(find.byKey(PlannerActionKeys.row('P08', _intermediate)));
    expect(
      harness.controller.active.state.value.completedSteps,
      contains(_intermediate),
    );
    await tester.pump();
    expect(find.byKey(_feedback), findsNothing);
    expect(
      find.byKey(PlannerActionKeys.row('P08', _intermediate)),
      findsNothing,
    );
    await _dispose(tester, harness);
  });

  testWidgets(
    'reset, target change and unmount discard retained presentation',
    (tester) async {
      final harness = await _mount(tester);
      await tester.tap(find.byKey(PlannerActionKeys.row('P08', _intermediate)));
      await tester.pump();
      expect(find.byKey(_feedback), findsOneWidget);
      harness.controller.active.resetCompleted();
      await tester.pump();
      expect(find.byKey(_feedback), findsNothing);
      harness.controller.active.commitInventory(_intermediate, '0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PlannerActionKeys.row('P08', _intermediate)));
      await tester.pump();
      harness.controller.active.selectTarget(_intermediate);
      await tester.pump();
      expect(find.byKey(_feedback), findsNothing);
      await _dispose(tester, harness);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving the visible Planner clears completion animation', (
    tester,
  ) async {
    final harness = await _mount(tester);
    await tester.tap(find.byKey(PlannerActionKeys.row('P08', _intermediate)));
    await tester.pump();
    await tester.pumpWidget(
      TickerMode(enabled: false, child: harness.plannerHost()),
    );
    await tester.pump();
    expect(find.byKey(_feedback), findsNothing);
    await _dispose(tester, harness);
  });

  for (final reduced in [false, true]) {
    testWidgets('substitute updates immediately with reduced motion $reduced', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduced);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final harness = await _mount(tester);
      await tester.tap(
        find.byKey(
          PlannerActionKeys.row('P12', 'step:Intermediate Reagent:Wild Herbs'),
        ),
      );
      await tester.pump();
      final chooser = find.byKey(
        const ValueKey('planner-choice-entrance:Sunrise Herb'),
      );
      expect(chooser, reduced ? findsNothing : findsOneWidget);
      await tester.tap(
        find.byKey(PlannerActionKeys.row('P13', 'Silver Azalea')),
      );
      expect(
        harness.controller.active.state.value.substituteChoices.values,
        contains('Silver Azalea'),
      );
      await tester.pump();
      expect(chooser, findsNothing);
      final feedback = find.byKey(
        const ValueKey('planner-choice-feedback:Silver Azalea'),
      );
      expect(feedback, reduced ? findsNothing : findsWidgets);
      if (!reduced) {
        final box = find
            .descendant(of: feedback.first, matching: find.byType(DecoratedBox))
            .first;
        double alpha() =>
            (tester.widget<DecoratedBox>(box).decoration as BoxDecoration)
                .color!
                .a;
        expect(alpha(), greaterThan(0));
        await tester.pump(const Duration(milliseconds: 150));
        expect(alpha(), 0);
      }
      await _dispose(tester, harness);
    });
  }
}

Future<PlannerTestHarness> _mount(WidgetTester tester) async {
  await setPlannerTestSize(tester, const Size(1500, 940));
  final harness = PlannerTestHarness();
  await tester.pumpWidget(
    TickerMode(enabled: true, child: harness.plannerHost()),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _dispose(WidgetTester tester, PlannerTestHarness harness) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await harness.controller.dispose();
  expect(tester.takeException(), isNull);
}
