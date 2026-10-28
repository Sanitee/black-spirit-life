import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_content_fit.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_quantity_layout.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  for (final spec in [
    SakuraNightGardenSpec.theme,
    IlluminatedLedgerSpec.theme,
    StandardSpec.theme,
  ]) {
    for (final textScale in [1.0, 1.5, 2.0]) {
      testWidgets(
        '${spec.id} $textScale queue and Need thresholds match actual geometry',
        (tester) async {
          await setPlannerTestSize(tester, const Size(2000, 1100));
          final harness = PlannerTestHarness();
          addTearDown(harness.controller.dispose);
          late List<double> thresholds;
          await tester.pumpWidget(
            _host(
              harness,
              spec: spec,
              textScale: textScale,
              measure: (context) => thresholds = plannerQueueFitBreakpoints(
                context,
                harness.controller.active,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final controller = harness.controller.active;
          final step = controller.plan.value.steps.first;
          final bodyWidth = tester.getSize(find.byType(PlannerView)).width;
          final fraction = spec.usesDenseSplitLayout ? .48 : .54;
          final summaryWidth = tester
              .getSize(
                find.byKey(ValueKey('planner-step-summary:${step.name}')),
              )
              .width;
          final fields = [
            for (final label in ['Craft', 'Results', 'Need'])
              tester
                  .getSize(
                    find.byKey(
                      ValueKey('planner-craft-field:${step.name}:$label'),
                    ),
                  )
                  .width,
          ];
          final fullSummary = fields.reduce((a, b) => a + b) + 16;
          expect(
            thresholds,
            _containsNear(bodyWidth + (fullSummary - summaryWidth) / fraction),
          );
          final rowFinder = find.byType(PlannerIngredientRowLayout).first;
          final row = tester.widget<PlannerIngredientRowLayout>(rowFinder);
          final rowWidth = tester.getSize(rowFinder).width;
          final totalPainter = TextPainter(
            text: TextSpan(text: row.total.data, style: row.total.style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(textScale),
          )..layout();
          final totalTextWidth = totalPainter.width;
          totalPainter.dispose();
          final totalWidth = totalTextWidth + 12 + row.totalRightInset;
          final stackAt = row.iconWidth + 21 + textScale * 100 + totalWidth;
          expect(
            thresholds,
            _containsNear(bodyWidth + (stackAt - rowWidth) / fraction),
          );
          final ingredient = step.ingredients.first;
          final hasGrades = controller
              .availableIngredientGrades(
                parentName: ingredient.parentName,
                selectedName: ingredient.baseName,
              )
              .isNotEmpty;
          if (hasGrades) {
            final renderedTotalWidth =
                tester.getSize(find.byWidget(row.total)).width +
                12 +
                row.totalRightInset;
            final qualityAt =
                row.iconWidth + 21 + renderedTotalWidth + textScale * 330;
            expect(
              thresholds,
              _containsNear(bodyWidth + (qualityAt - rowWidth) / fraction),
            );
          }
          if (textScale <= 1.3) {
            expect(
              thresholds,
              _containsNear(bodyWidth + (330 - rowWidth) / fraction),
            );
          }
          final needFinder = find.byType(PlannerNeedQuantities).first;
          final need = tester.widget<PlannerNeedQuantities>(needFinder);
          final needWidth = tester.getSize(needFinder).width;
          final needFraction = spec.usesDenseSplitLayout ? .52 : .46;
          final needQuantityWrap = find.descendant(
            of: needFinder,
            matching: find.byWidgetPredicate(
              (widget) => widget is Wrap && widget.spacing == 16,
            ),
          );
          final needPairWidths = [
            for (final pair in tester.widget<Wrap>(needQuantityWrap).children)
              tester.getSize(find.byWidget(pair)).width,
          ];
          final needFullWidth = needPairWidths.reduce((a, b) => a + b) + 32;
          final sideBySide = 60 + textScale * 350;
          final stackedNeedWidth = needFullWidth + 60;
          if (stackedNeedWidth < sideBySide) {
            expect(
              thresholds,
              _containsNear(
                bodyWidth + (stackedNeedWidth - needWidth) / needFraction,
              ),
            );
          }
          final inlineNeedWidth =
              needFullWidth +
              60 +
              16 +
              tester.getSize(find.byWidget(need.actions)).width;
          if (inlineNeedWidth >= sideBySide) {
            expect(
              thresholds,
              _containsNear(
                bodyWidth + (inlineNeedWidth - needWidth) / needFraction,
              ),
            );
          }
          expect(thresholds, orderedEquals([...thresholds]..sort()));
          expect(thresholds.toSet(), hasLength(thresholds.length));
          expect(
            thresholds.every((value) => value.isFinite && value > 0),
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'unmounted later steps contribute without plan or state mutation',
    (tester) async {
      final harness = PlannerTestHarness();
      addTearDown(harness.controller.dispose);
      final controller = harness.controller.active;
      final original = controller.plan.value;
      final later = PlanStep(
        name: 'Later unmounted recipe',
        index: 99,
        count: 987654321,
        batchCount: 987654321,
        batchSize: 1,
        produced: 1234567890,
        demand: 1234567890,
        net: 1234567890,
        depth: 1,
        ingredients: const [],
      );
      controller.plan.value = PlanResult(
        target: original.target,
        want: original.want,
        steps: [...original.steps, later],
        missing: original.missing,
        empty: false,
      );
      final plan = controller.plan.value;
      final state = controller.state.value;
      final document = harness.controller.documentSnapshot;
      var planNotifications = 0;
      controller.plan.addListener(() => planNotifications++);
      late List<double> all;
      late List<double> firstOnly;
      await tester.pumpWidget(
        _host(
          harness,
          renderPlanner: false,
          measure: (context) {
            all = plannerQueueFitBreakpoints(context, controller);
            controller.plan.value = original;
            firstOnly = plannerQueueFitBreakpoints(context, controller);
            controller.plan.value = plan;
          },
        ),
      );
      expect(all.toSet().difference(firstOnly.toSet()), isNotEmpty);
      expect(find.byType(PlannerCraftQuantities), findsNothing);
      expect(controller.plan.value, same(plan));
      expect(controller.state.value, same(state));
      expect(harness.controller.documentSnapshot, same(document));
      expect(
        planNotifications,
        2,
        reason: 'Only the test fixture swaps its input plans.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('unmounted Need values contribute without rendering rows', (
    tester,
  ) async {
    final harness = PlannerTestHarness();
    addTearDown(harness.controller.dispose);
    final controller = harness.controller.active;
    final original = controller.plan.value;
    final first = original.missing.first;
    late List<double> before;
    late List<double> after;
    await tester.pumpWidget(
      _host(
        harness,
        renderPlanner: false,
        measure: (context) {
          before = plannerQueueFitBreakpoints(context, controller);
          controller.plan.value = PlanResult(
            target: original.target,
            want: original.want,
            steps: original.steps,
            missing: [
              ...original.missing,
              MissingMaterial(
                name: 'Later unmounted need',
                key: 'later-need',
                category: first.category,
                need: 1234567890,
                have: 987654321,
                missing: 246913569,
                choice: null,
                market: first.market,
              ),
            ],
            empty: false,
          );
          after = plannerQueueFitBreakpoints(context, controller);
        },
      ),
    );
    expect(after.toSet().difference(before.toSet()), isNotEmpty);
    expect(find.byType(PlannerNeedQuantities), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Matcher _containsNear(double expected) => contains(
  predicate<double>(
    (value) => (value - expected).abs() < .02,
    'within .02 of $expected',
  ),
);

Widget _host(
  PlannerTestHarness harness, {
  ThemeSpec spec = StandardSpec.theme,
  double textScale = 1,
  bool renderPlanner = true,
  required void Function(BuildContext) measure,
}) => AppOverlayCoordinatorHost(
  child: MaterialApp(
    theme: spec.materialTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: ThemeSpecScope(
      spec: spec,
      child: Scaffold(
        body: Builder(
          builder: (context) {
            measure(context);
            return renderPlanner
                ? PlannerView(
                    controller: harness.controller.active,
                    externalActions: harness.actions,
                  )
                : const SizedBox.shrink();
          },
        ),
      ),
    ),
  ),
);
