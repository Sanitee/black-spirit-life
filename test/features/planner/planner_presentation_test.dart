import 'dart:convert';

import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_interaction_frame.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  for (final spec in [
    StandardSpec.theme,
    SakuraNightGardenSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final reduced in [false, true]) {
      testWidgets(
        '${spec.id} queue lighting is finite and presentation only, reduced $reduced',
        (tester) async {
          await setPlannerTestSize(tester, const Size(1500, 940));
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(disableAnimations: reduced);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
          final harness = PlannerTestHarness();
          addTearDown(harness.controller.dispose);
          await tester.pumpWidget(harness.plannerHost(spec: spec));
          await tester.pumpAndSettle();
          final controller = harness.controller.active;
          final step = controller.plan.value.steps.first;
          final card = find.byKey(ValueKey('queue:${step.name}'));
          final frame = find
              .descendant(of: card, matching: find.byType(AppInteractionFrame))
              .first;
          final paint = find
              .descendant(
                of: frame,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is CustomPaint &&
                      widget.foregroundPainter is AppInteractionEdgePainter,
                ),
              )
              .first;
          AppInteractionEdgePainter painter() =>
              tester.widget<CustomPaint>(paint).foregroundPainter!
                  as AppInteractionEdgePainter;
          final bounds = tester.getRect(card);
          final originalPlan = controller.plan.value;
          final originalState = jsonEncode(controller.state.value.toJson());
          final summary = find.byKey(
            ValueKey('planner-step-summary:${step.name}'),
          );
          final summaryElement = tester.element(summary);
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(1490, 930));
          await mouse.moveTo(bounds.topLeft + const Offset(6, 6));
          await tester.pump();
          if (!reduced) {
            await tester.pump(const Duration(milliseconds: 80));
            expect(painter().light.value, inExclusiveRange(0, 1));
          }
          await tester.pumpAndSettle();
          expect(painter().light.value, 1);
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.element(summary), same(summaryElement));
          expect(tester.getRect(card), bounds);
          expect(controller.plan.value, same(originalPlan));
          expect(jsonEncode(controller.state.value.toJson()), originalState);
          expect(painter().hitTest(Offset.zero), isFalse);
          await mouse.moveTo(const Offset(1490, 930));
          await tester.pumpAndSettle();
          expect(painter().light.value, 0);
          expect(tester.binding.transientCallbackCount, 0);
          // Existing controls, not the decoration, remain the action owners.
          await tester.tap(find.byKey(PlannerActionKeys.row('P09', step.name)));
          await tester.pumpAndSettle();
          expect(controller.plan.value, same(originalPlan));
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
