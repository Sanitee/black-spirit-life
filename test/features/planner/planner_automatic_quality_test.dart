import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  for (final spec in [
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
    SakuraNightGardenSpec.theme,
  ]) {
    testWidgets(
      'market refresh selects and highlights the available quality in ${spec.id}',
      (tester) async {
        await setPlannerTestSize(tester, const Size(1500, 940));
        final harness = PlannerTestHarness(
          sunriseNpcPrice: 0,
          supportingDataOverrides: const {
            'marketIds': {
              'Sunrise Herb': '5401',
              'Silver Azalea': '5402',
              'High-Quality Sunrise Herb': '5403',
              'Special Sunrise Herb': '5404',
              'High-Quality Silver Azalea': '5405',
              'Special Silver Azalea': '5406',
            },
          },
          marketRefresh: const PlannerMarketRefresh(
            prices: {'Sunrise Herb': 1, 'Special Sunrise Herb': 100},
            stock: {
              'Sunrise Herb': 0,
              'High-Quality Sunrise Herb': 0,
              'Special Sunrise Herb': 2,
              'Silver Azalea': 0,
              'High-Quality Silver Azalea': 0,
              'Special Silver Azalea': 0,
            },
            unlistedItemNames: {},
            fetchedAt: 42,
            summary: 'Prices checked.',
          ),
        );
        addTearDown(harness.controller.dispose);
        await tester.pumpWidget(harness.plannerHost(spec: spec));
        await tester.pumpAndSettle();
        final mode = harness.controller.active;
        expect(mode.plan.value.missing.single.name, 'Sunrise Herb');
        await tester.tap(find.byKey(PlannerActionKeys.p15));
        await tester.pumpAndSettle();

        expect(
          harness.marketRequest!.namesForRefresh,
          containsAll([
            'Sunrise Herb',
            'High-Quality Sunrise Herb',
            'Special Sunrise Herb',
            'Silver Azalea',
            'High-Quality Silver Azalea',
            'Special Silver Azalea',
          ]),
        );
        expect(mode.plan.value.missing.single.name, 'Special Sunrise Herb');
        expect(find.byKey(const ValueKey('need:Sunrise Herb')), findsNothing);
        expect(
          find.byKey(const ValueKey('need:Special Sunrise Herb')),
          findsOneWidget,
        );
        expect(find.text('Stock 2'), findsOneWidget);
        expect(find.text('Out of stock'), findsNothing);
        expect(mode.state.value.ingredientGrades, isEmpty);

        // Assert the actual button's selected state, not a saved preference.
        final special = find.descendant(
          of: find.byKey(
            PlannerActionKeys.row('P14', 'Intermediate Reagent:Sunrise Herb'),
          ),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Special Grade quality',
          ),
        );
        expect(special, findsOneWidget);
        expect(tester.widget<Semantics>(special).properties.selected, isTrue);

        mode.updateState(
          (state) => state.copyWith(
            ignoreIngredientInventory: false,
            inventory: {'Sunrise Herb': 1000},
          ),
          immediate: true,
        );
        await tester.pumpAndSettle();
        final row = mode.plan.value.steps
            .singleWhere((step) => step.name == 'Intermediate Reagent')
            .ingredients
            .single;
        expect(row.name, 'Sunrise Herb');
        expect(mode.plan.value.missing, isEmpty);
        expect(tester.widget<Semantics>(special).properties.selected, isFalse);
        expect(mode.state.value.ingredientGrades, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
