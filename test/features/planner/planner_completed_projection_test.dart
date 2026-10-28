import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_completed_projection.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import 'planner_test_fixture.dart';

void main() {
  testWidgets(
    'Completed expands deliberately, survives theme repaint and resets per queue',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(includeQueueTitleSubstitutes: true);
      addTearDown(harness.controller.dispose);
      final mode = harness.controller.active;
      mode.updateState(
        (state) => state.copyWith(
          ignoreIngredientInventory: false,
          inventory: {'Intermediate Reagent': 10},
          substituteChoices: {
            'recipe:Clear Liquid Reagent:Reagent Base': 'Intermediate Reagent',
          },
        ),
      );
      final button = find.byKey(const ValueKey('planner-completed-disclosure'));
      final covered = find.byKey(
        const ValueKey('planner-completed-step:Intermediate Powder'),
      );
      await tester.pumpWidget(harness.plannerHost());
      await tester.pumpAndSettle();
      expect(find.text('Completed 2'), findsOneWidget);
      expect(covered, findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(covered, findsOneWidget);
      final before = harness.controller.documentSnapshot;
      await tester.pumpWidget(
        harness.plannerHost(spec: SakuraNightGardenSpec.theme),
      );
      await tester.pumpAndSettle();
      expect(covered, findsOneWidget);
      expect(harness.controller.documentSnapshot, same(before));

      await tester.tap(find.text('Restart queue'));
      await tester.pumpAndSettle();
      expect(mode.state.value.completedSteps, isEmpty);
      expect(find.text('Completed 2'), findsOneWidget);
      expect(
        covered,
        findsNothing,
        reason: 'Restart also hides unmarked coverage.',
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(covered, findsOneWidget);

      mode.commitAmount('20');
      await tester.pumpAndSettle();
      expect(button, findsNothing);
      mode.commitQueueInventory('Intermediate Reagent', '30');
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      expect(covered, findsNothing, reason: 'A new amount starts collapsed.');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(covered, findsOneWidget);

      harness.controller.switchMode(CraftMode.processing);
      await tester.pumpWidget(harness.plannerHost());
      await tester.pumpAndSettle();
      harness.controller.switchMode(CraftMode.alchemy);
      await tester.pumpWidget(harness.plannerHost());
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      expect(
        covered,
        findsNothing,
        reason: 'Switching modes cannot leak expansion.',
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      mode.selectTarget('Intermediate Reagent');
      mode.commitQueueInventory('Intermediate Reagent', '30');
      await tester.pumpAndSettle();
      expect(find.text('Completed 2'), findsOneWidget);
      expect(covered, findsNothing, reason: 'A new target starts collapsed.');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'real Edania stock covers its full upstream chain rather than only draughts',
    () async {
      final harness = await ApplicationTestHarness.create();
      addTearDown(harness.dispose);
      final controller = harness.bundle.controller;
      final mode = controller.active;
      const target = 'Harmony Draught - Edania';
      mode.selectTarget(target);
      mode.updateState(
        (state) => state.copyWith(
          want: 100,
          ignoreIngredientInventory: false,
          ignoreTargetInventory: false,
          inventory: const {},
        ),
      );
      final fromZero = mode.plan.value.steps
          .map((step) => step.name)
          .toList(growable: false);
      expect(fromZero.length, greaterThan(25));
      expect(
        fromZero,
        containsAll([
          'Clear Liquid Reagent',
          'Pure Powder Reagent',
          "Sinner's Blood",
          'Elixir of Edania',
          'Elixir of Will',
          'Fury Draught',
          'Adaptation Draught',
          'Potential Draught',
          'Corruption Draught',
          'Berserk Draught',
          'Harmony Draught',
          target,
        ]),
      );

      // Owned final inputs must cover their deeper reagents, oils and elixirs
      // even though none of those absent upstream steps was checkmarked.
      mode.updateState(
        (state) => state.copyWith(
          inventory: const {
            'Harmony Draught': 1000,
            'Elixir of Edania': 1000,
            'Elixir of Will': 1000,
          },
        ),
      );
      final projection = PlannerCompletedProjection();
      final document = controller.documentSnapshot;
      final plan = mode.plan.value;
      final covered = projection.namesFor(mode);
      expect(plan.steps.map((step) => step.name), [target]);
      expect(covered, fromZero.where((name) => name != target).toList());
      expect(covered.toSet().length, covered.length);
      expect(covered, isNot(contains(target)));
      expect(
        covered,
        isNot(
          anyOf(
            contains('Salt'),
            contains('Weeds'),
            contains('Concentrated Spellbound Catalyst'),
          ),
        ),
        reason: 'Raw leaves and NPC-only inputs are not craft steps.',
      );
      expect(mode.state.value.completedSteps, isEmpty);
      expect(controller.documentSnapshot, same(document));
      expect(mode.plan.value, same(plan));

      // If only the five lower draughts are owned, Harmony itself remains work.
      mode.updateState(
        (state) => state.copyWith(
          inventory: const {
            'Fury Draught': 1000,
            'Adaptation Draught': 1000,
            'Potential Draught': 1000,
            'Corruption Draught': 1000,
            'Berserk Draught': 1000,
            'Elixir of Edania': 1000,
            'Elixir of Will': 1000,
          },
        ),
      );
      expect(mode.plan.value.steps.map((step) => step.name), [
        'Harmony Draught',
        target,
      ]);
      expect(
        projection.namesFor(mode),
        fromZero
            .where((name) => name != target && name != 'Harmony Draught')
            .toList(),
      );
      expect(mode.state.value.completedSteps, isEmpty);
    },
  );

  test(
    'owned parent covers the full selected upstream chain, not raw stock',
    () async {
      final harness = PlannerTestHarness(includeQueueTitleSubstitutes: true);
      addTearDown(harness.controller.dispose);
      final mode = harness.controller.active;
      mode.updateState(
        (state) => state.copyWith(
          ignoreIngredientInventory: false,
          inventory: {
            'Intermediate Reagent': 10,
            'Pure Powder Reagent': 1000,
            'Sunrise Herb': 1000,
          },
          substituteChoices: {
            'recipe:Clear Liquid Reagent:Reagent Base': 'Intermediate Reagent',
          },
        ),
      );
      final projection = PlannerCompletedProjection();
      final before = harness.controller.documentSnapshot;
      final plan = mode.plan.value;
      final names = projection.namesFor(mode);
      expect(names, ['Intermediate Powder', 'Intermediate Reagent']);
      expect(mode.state.value.completedSteps, isEmpty);
      expect(harness.controller.documentSnapshot, same(before));
      expect(mode.plan.value, same(plan));
      expect(
        projection.namesFor(mode),
        same(names),
        reason: 'Repaints reuse the projection.',
      );

      mode.commitQueueInventory('Intermediate Reagent', '1');
      expect(
        projection.namesFor(mode),
        isEmpty,
        reason: 'Partially covered work still belongs in the active queue.',
      );
      mode.commitQueueInventory('Intermediate Reagent', '10');
      expect(projection.namesFor(mode), [
        'Intermediate Powder',
        'Intermediate Reagent',
      ]);
      mode.updateState(
        (state) => state.copyWith(ignoreIngredientInventory: true),
      );
      expect(
        projection.namesFor(mode),
        isEmpty,
        reason: 'Ignored stock cannot mark work covered.',
      );
      mode.updateState(
        (state) => state.copyWith(ignoreIngredientInventory: false),
      );
      expect(projection.namesFor(mode), [
        'Intermediate Powder',
        'Intermediate Reagent',
      ]);
    },
  );

  test(
    'owned target covers all crafts and zero requested output covers none',
    () async {
      final harness = PlannerTestHarness(includeQueueTitleSubstitutes: true);
      addTearDown(harness.controller.dispose);
      final mode = harness.controller.active;
      mode.updateState(
        (state) => state.copyWith(
          ignoreIngredientInventory: false,
          ignoreTargetInventory: false,
          inventory: {'Clear Liquid Reagent': 10},
          substituteChoices: {
            'recipe:Clear Liquid Reagent:Reagent Base': 'Intermediate Reagent',
          },
        ),
      );
      final projection = PlannerCompletedProjection();
      expect(projection.namesFor(mode), [
        'Intermediate Powder',
        'Intermediate Reagent',
        'Clear Liquid Reagent',
      ]);
      mode.commitAmount('20');
      expect(projection.namesFor(mode), isEmpty);
      mode.updateState((state) => state.copyWith(want: 0));
      expect(projection.namesFor(mode), isEmpty);
    },
  );

  test(
    'Auto uses the real owned substitute and retains its consumed branch',
    () async {
      final harness = PlannerTestHarness(includeQueueTitleSubstitutes: true);
      addTearDown(harness.controller.dispose);
      final mode = harness.controller.active;
      mode.commitQueueInventory('Alternate Reagent', '10');
      final projection = PlannerCompletedProjection();
      expect(
        mode.plan.value.steps.single.ingredients.single.name,
        'Alternate Reagent',
      );
      expect(projection.namesFor(mode), ['Alternate Reagent']);
      expect(mode.completeStep(mode.plan.value.steps.single), isTrue);
      expect(mode.state.value.inventory['Alternate Reagent'] ?? 0, 0);
      expect(projection.namesFor(mode), [
        'Alternate Reagent',
        'Clear Liquid Reagent',
      ]);
      expect(
        mode.state.value.substituteChoices,
        isEmpty,
        reason: 'Temporary Auto pins are never persisted.',
      );
    },
  );

  test(
    'explicit substitute and batch switches cannot retain the old branch',
    () async {
      final harness = PlannerTestHarness(includeQueueTitleSubstitutes: true);
      addTearDown(harness.controller.dispose);
      final mode = harness.controller.active;
      mode.commitQueueInventory('Alternate Reagent', '10');
      mode.commitQueueInventory('Intermediate Reagent', '10');
      final projection = PlannerCompletedProjection();
      final input = mode
          .recipeDefinition('Clear Liquid Reagent')!
          .ingredients
          .single;
      mode.selectSubstitute(
        parentName: 'Clear Liquid Reagent',
        ingredient: input,
        selection: 'Intermediate Reagent',
      );
      expect(projection.namesFor(mode), [
        'Intermediate Powder',
        'Intermediate Reagent',
      ]);
      mode.selectSubstitute(
        parentName: 'Clear Liquid Reagent',
        ingredient: input,
        selection: 'Alternate Reagent',
      );
      expect(projection.namesFor(mode), ['Alternate Reagent']);

      final batches = PlannerTestHarness(includeRecipeVariants: true);
      addTearDown(batches.controller.dispose);
      final other = batches.controller.active;
      other.commitQueueInventory('Intermediate Reagent', '100');
      other.selectRecipeVariant(
        recipeName: 'Clear Liquid Reagent',
        variantId: 'reagent-route-10x',
      );
      expect(projection.namesFor(other), ['Intermediate Reagent']);
      other.selectRecipeVariant(
        recipeName: 'Clear Liquid Reagent',
        variantId: 'herb-route-10x',
      );
      expect(projection.namesFor(other), isEmpty);
    },
  );

  test(
    'selected quality follows its actual craftable item rather than its base',
    () async {
      final harness = PlannerTestHarness();
      addTearDown(harness.controller.dispose);
      final mode = harness.controller.active;
      mode.updateState(
        (state) => state.copyWith(
          recipeEdits: {
            'High-Quality Sunrise Herb': RecipeState(
              type: 'alchemy',
              baseOutput: 1,
              outputMinimum: 1,
              outputMaximum: 1,
              ingredients: [
                IngredientState(name: 'Raw Test Leaf', quantity: 1),
              ],
            ),
          },
        ),
      );
      mode.commitQueueInventory('High-Quality Sunrise Herb', '100');
      mode.selectIngredientGrade(
        parentName: 'Intermediate Reagent',
        ingredientName: 'Sunrise Herb',
        selectedName: 'Sunrise Herb',
        grade: 'high',
      );
      final projection = PlannerCompletedProjection();
      expect(projection.namesFor(mode), ['High-Quality Sunrise Herb']);
      mode.selectIngredientGrade(
        parentName: 'Intermediate Reagent',
        ingredientName: 'Sunrise Herb',
        selectedName: 'Sunrise Herb',
        grade: 'normal',
      );
      expect(projection.namesFor(mode), isEmpty);
    },
  );

  test(
    'consumed completions retain dependency order and Undo/Restart stay intact',
    () async {
      final harness = PlannerTestHarness(includeQueueTitleSubstitutes: true);
      addTearDown(harness.controller.dispose);
      final mode = harness.controller.active;
      mode.updateState(
        (state) => state.copyWith(
          substituteChoices: {
            'recipe:Clear Liquid Reagent:Reagent Base': 'Intermediate Reagent',
          },
        ),
      );
      final projection = PlannerCompletedProjection();
      expect(projection.namesFor(mode), isEmpty);
      for (final name in [
        'Intermediate Powder',
        'Intermediate Reagent',
        'Clear Liquid Reagent',
      ]) {
        final step = mode.plan.value.steps.singleWhere(
          (step) => step.name == name,
        );
        expect(mode.completeStep(step), isTrue);
        projection.namesFor(mode);
      }
      expect(mode.state.value.inventory['Intermediate Powder'] ?? 0, 0);
      expect(mode.state.value.inventory['Intermediate Reagent'] ?? 0, 0);
      expect(projection.namesFor(mode), [
        'Intermediate Powder',
        'Intermediate Reagent',
        'Clear Liquid Reagent',
      ]);
      expect(mode.undoCompletion(), isTrue);
      expect(projection.namesFor(mode), [
        'Intermediate Powder',
        'Intermediate Reagent',
      ]);
      final inventory = mode.state.value.inventory;
      mode.resetCompleted();
      expect(mode.state.value.completedSteps, isEmpty);
      expect(mode.state.value.inventory, inventory);
      expect(
        projection.namesFor(mode),
        isEmpty,
        reason: 'Restart clears craft credits while Ignore owned stays on.',
      );
      mode.setIgnoreOwnedIngredients(false);
      // The real output remains in inventory and can explicitly be used again.
      expect(projection.namesFor(mode), [
        'Intermediate Powder',
        'Intermediate Reagent',
      ]);
    },
  );
}
