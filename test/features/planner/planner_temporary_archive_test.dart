import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  testWidgets(
    'raw archived options stay in saved formulas but not the Planner chooser',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();
      final mode = harness.controller.active;
      mode.updateState(
        (state) => state.copyWith(
          recipeEdits: {
            ...state.recipeEdits,
            'Intermediate Reagent': RecipeState(
              type: 'alchemy',
              ingredients: [
                IngredientState(
                  name: 'Sunrise Herb',
                  quantity: 1,
                  options: ['Sunrise Herb', 'Silver Azalea', 'Monkey Blood'],
                  substituteGroup: 'Wild Herbs',
                ),
              ],
            ),
          },
        ),
      );
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));
      final before = mode.state.value.toJson();
      await tester.tap(
        find.byKey(
          PlannerActionKeys.row('P12', 'step:Intermediate Reagent:Wild Herbs'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(PlannerActionKeys.row('P13', 'Sunrise Herb')),
        findsOneWidget,
      );
      expect(
        find.byKey(PlannerActionKeys.row('P13', 'Silver Azalea')),
        findsOneWidget,
      );
      expect(
        find.byKey(PlannerActionKeys.row('P13', 'Monkey Blood')),
        findsNothing,
      );
      expect(find.text('Monkey Blood'), findsNothing);
      expect(mode.state.value.toJson(), before);
      expect(
        mode
            .state
            .value
            .recipeEdits['Intermediate Reagent']!
            .ingredients
            .single
            .options,
        contains('Monkey Blood'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.controller.dispose();
    },
  );
}
