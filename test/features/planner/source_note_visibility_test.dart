import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  testWidgets(
    'vendor metadata shows the Need First source information action',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final harness = PlannerTestHarness(
        supportingDataOverrides: const <String, Object?>{
          'vendorInfo': <String, Object?>{
            'Sunrise Herb': <String, Object?>{
              'vendor': 'Material Vendor',
              'role': 'Material Vendor',
              'location': 'Heidel',
              'price': 500,
            },
          },
          'acquisitionInfo': <String, Object?>{
            'Sunrise Herb': <String, Object?>{
              'canonicalName': 'Sunrise Herb',
              'status': 'reviewed',
              'reviewedAt': '2026-08-10',
              'routes': <Object?>[
                <String, Object?>{
                  'kind': 'npc_purchase',
                  'summary': 'Buy from a Material Vendor in Heidel.',
                  'availability': 'permanent',
                  'confidence': 'high',
                },
              ],
            },
          },
        },
      );
      harness.controller.active.updateState(
        (state) => state.copyWith(
          ingredientMeta: const <String, IngredientMetadata>{},
          recipeEdits: const <String, RecipeState?>{},
        ),
      );

      final market = harness.controller.active.plan.value.missing
          .singleWhere((row) => row.name == 'Sunrise Herb')
          .market;
      expect(market.status, 'vendor');
      expect(market.price, 500);
      expect(market.hasSourceInfo, isTrue);
      await _expectSourceIconAcrossPlannerAndBonus(
        tester,
        harness,
        visible: true,
        expectedBodyText: <String>[
          'Buy from a Material Vendor in Heidel.',
          'Vendor: Material Vendor - Heidel',
        ],
      );
      await harness.controller.dispose();
    },
  );

  testWidgets('custom gathering note stays out of the compact source action', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();
    harness.controller.active.updateState(
      (state) => state.copyWith(
        ingredientMeta: <String, IngredientMetadata>{
          'Sunrise Herb': IngredientMetadata(
            category: 'Herbs',
            sourceNote: 'Gathered near Heidel roads.',
          ),
        },
      ),
    );

    await _expectSourceIconAcrossPlannerAndBonus(
      tester,
      harness,
      visible: false,
    );
    await harness.controller.dispose();
  });

  testWidgets('persisted gathering note stays out of the source action', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();
    harness.controller.active.updateState(
      (state) => state.copyWith(
        ingredientMeta: const <String, IngredientMetadata>{},
        recipeEdits: <String, RecipeState?>{
          'Sunrise Herb': RecipeState(
            type: 'gathered',
            baseOutput: 1,
            group: 'Materials',
            sourceNote: 'My saved gathering route',
          ),
        },
      ),
    );

    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));
    final action = find.byKey(PlannerActionKeys.row('P17', 'Sunrise Herb'));
    expect(action, findsNothing);
    await harness.controller.dispose();
  });

  testWidgets(
    'known provenance stays hidden while useful vendor details remain',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final harness = PlannerTestHarness();
      const provenance =
          'Imported from BDOLytics recipe 9077; icons and item IDs checked through BDO Codex.';
      harness.controller.active.updateState(
        (state) => state.copyWith(
          ingredientMeta: <String, IngredientMetadata>{
            'Sunrise Herb': IngredientMetadata(
              sourceNote: provenance,
              vendor: 'Material Vendor',
              location: 'Heidel',
              npcPrice: 500,
            ),
          },
        ),
      );

      await _expectSourceIconAcrossPlannerAndBonus(
        tester,
        harness,
        visible: true,
        expectedBodyText: <String>['Vendor: Material Vendor - Heidel'],
      );
      expect(find.textContaining('Imported from BDO'), findsNothing);
      await harness.controller.dispose();
    },
  );

  testWidgets('reviewed NPC purchase route shows without vendor metadata', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness(
      supportingDataOverrides: const <String, Object?>{
        'vendorInfo': <String, Object?>{},
        'acquisitionInfo': <String, Object?>{
          'Sunrise Herb': <String, Object?>{
            'canonicalName': 'Sunrise Herb',
            'status': 'reviewed',
            'reviewedAt': '2026-08-10',
            'routes': <Object?>[
              <String, Object?>{
                'kind': 'npc_purchase',
                'summary': 'Buy from a Material Vendor.',
                'availability': 'permanent',
                'confidence': 'high',
              },
            ],
          },
        },
      },
    );
    harness.controller.active.updateState(
      (state) => state.copyWith(
        ingredientMeta: const <String, IngredientMetadata>{},
        recipeEdits: const <String, RecipeState?>{},
      ),
    );

    await _expectSourceIconAcrossPlannerAndBonus(
      tester,
      harness,
      visible: true,
      expectedBodyText: <String>['Buy from a Material Vendor.'],
    );
    await harness.controller.dispose();
  });

  testWidgets('ordinary category metadata does not show a source action', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness(
      supportingDataOverrides: const <String, Object?>{
        'vendorInfo': <String, Object?>{},
      },
    );
    harness.controller.active.updateState(
      (state) => state.copyWith(
        ingredientMeta: const <String, IngredientMetadata>{},
        recipeEdits: const <String, RecipeState?>{},
      ),
    );

    await _expectSourceIconAcrossPlannerAndBonus(
      tester,
      harness,
      visible: false,
    );
    await harness.controller.dispose();
  });
}

Future<void> _expectSourceIconAcrossPlannerAndBonus(
  WidgetTester tester,
  PlannerTestHarness harness, {
  required bool visible,
  List<String> expectedBodyText = const <String>[],
}) async {
  final expected = visible ? findsOneWidget : findsNothing;
  final action = find.byKey(PlannerActionKeys.row('P17', 'Sunrise Herb'));

  await tester.pumpWidget(harness.plannerHost());
  await tester.pump(const Duration(milliseconds: 200));
  expect(action, expected);
  if (visible) {
    expect(
      find.descendant(of: action, matching: find.text('?')),
      findsOneWidget,
    );
    await tester.tap(action);
    await tester.pump();
    for (final text in expectedBodyText) {
      expect(find.textContaining(text), findsOneWidget);
    }
  }

  await tester.pumpWidget(harness.bonusHost());
  await tester.pump(const Duration(milliseconds: 200));
  expect(action, expected);
  if (visible) {
    expect(
      find.descendant(of: action, matching: find.text('?')),
      findsOneWidget,
    );
    await tester.tap(action);
    await tester.pump();
    for (final text in expectedBodyText) {
      expect(find.textContaining(text), findsOneWidget);
    }
  }
}
