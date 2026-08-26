import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/planner/planner_test_fixture.dart';

void main() {
  testWidgets('AFK Weight keeps its plan readable at a glance', (tester) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(
      supportingDataOverrides: const <String, Object?>{
        'itemWeightIds': <String, String>{
          'Intermediate Reagent': '1001',
          'Sunrise Herb': '1002',
        },
        'itemWeightsLtById': <String, double>{'1001': 2, '1002': 1},
      },
    );
    harness.controller.updateDocument(
      (document) => document.copyWith(
        afkWeightProfile: document.afkWeightProfile.copyWith(
          maximumWeightLt: 6200,
          currentCarriedWeightLt: 100,
          safetyBufferLt: 50,
        ),
        alchemy: document.alchemy.copyWith(want: 1585),
      ),
      immediate: true,
    );

    await tester.pumpWidget(
      harness.plannerHost(spec: SakuraNightGardenSpec.theme),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('planner-afk-load:alchemy:Intermediate Reagent'),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppSurface &&
            widget.semanticLabel == 'AFK Weight plan for Intermediate Reagent',
      ),
      matchesGoldenFile('afk_weight_popover_sakura.png'),
    );
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });
}
