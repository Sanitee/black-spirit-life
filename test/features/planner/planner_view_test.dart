import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_shared.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_vector_glyph.dart';
import 'package:bdo_craft_planner_flutter/visual/components/section_header.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_ornament_painters.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_botanical_assets.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/custom_icon_test_support.dart';
import 'planner_test_fixture.dart';

void main() {
  testWidgets(
    'AFK Load defaults to the Planner target and keeps Maximum explicit',
    (tester) async {
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

      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      final anchor = find.byKey(
        const ValueKey<String>('planner-afk-load:alchemy:Intermediate Reagent'),
      );
      expect(anchor, findsOneWidget);
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      expect(find.text('Open weight settings'), findsOneWidget);
      await tester.tap(find.text('Open weight settings'));
      await tester.pumpAndSettle();
      expect(harness.afkWeightSettingsOpenCount, 1);

      harness.controller.updateDocument(
        (document) => document.copyWith(
          afkWeightProfile: document.afkWeightProfile.copyWith(
            maximumWeightLt: 100,
            currentCarriedWeightLt: 10,
            safetyBufferLt: 10,
          ),
        ),
        immediate: true,
      );
      await tester.pumpAndSettle();

      await tester.tap(anchor);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey<String>('planner-afk-mode-needed')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('planner-afk-needed-attempts')),
            )
            .data,
        '10 attempts',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('planner-afk-goal-label')),
            )
            .data,
        'For 10 Clear Liquid Reagent',
      );
      expect(find.text('Sunrise Herb'), findsWidgets);
      expect(find.text('20 x'), findsOneWidget);
      final neededPerAttempt = find.byKey(
        const ValueKey<String>('planner-afk-per-attempt:Sunrise Herb'),
      );
      expect(neededPerAttempt, findsOneWidget);
      expect(tester.widget<Text>(neededPerAttempt).data, '2 / attempt');
      expect(
        tester.widget<Text>(neededPerAttempt).style?.color,
        StandardSpec.theme.palette.text,
      );
      final afkDragRegion = find.byKey(
        const ValueKey<String>('planner-afk-drag-region'),
      );
      expect(afkDragRegion, findsOneWidget);
      expect(
        find.descendant(
          of: afkDragRegion,
          matching: find.byKey(
            const ValueKey<String>('planner-afk-edit-profile'),
          ),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-copy-load')),
      );
      await tester.pump();
      expect(harness.copiedAfkLoads, hasLength(1));
      expect(
        harness.copiedAfkLoads.single,
        contains('Planner goal: 10 x Clear Liquid Reagent'),
      );
      expect(
        harness.copiedAfkLoads.single,
        contains('This recipe: 10 attempts'),
      );
      expect(
        harness.copiedAfkLoads.single,
        contains('Round 1 of 1: 10 attempts'),
      );
      expect(harness.copiedAfkLoads.single, contains('20 x Sunrise Herb'));

      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-mode-maximum')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey<String>('planner-afk-mode-maximum')),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('planner-afk-safe-attempts')),
            )
            .data,
        '40 attempts',
      );
      final maximumPerAttempt = find.byKey(
        const ValueKey<String>('planner-afk-per-attempt:Sunrise Herb'),
      );
      expect(tester.widget<Text>(maximumPerAttempt).data, '2 / attempt');
      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-copy-load')),
      );
      await tester.pump();
      expect(harness.copiedAfkLoads, hasLength(2));
      expect(harness.copiedAfkLoads.last, contains('Maximum safe load'));
      expect(harness.copiedAfkLoads.last, contains('Safe attempts: 40'));
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'AFK Load persists numbered rounds and uses a final partial load',
    (tester) async {
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
            maximumWeightLt: 100,
            currentCarriedWeightLt: 10,
            safetyBufferLt: 10,
          ),
          alchemy: document.alchemy.copyWith(want: 90),
        ),
        immediate: true,
      );

      await tester.pumpWidget(harness.plannerHost());
      await tester.pumpAndSettle();

      const anchorKey = ValueKey<String>(
        'planner-afk-load:alchemy:Intermediate Reagent',
      );
      final anchor = find.byKey(anchorKey);
      await tester.tap(anchor);
      await tester.pumpAndSettle();

      void expectRound(String label, String attempts, String ingredientCount) {
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey<String>('planner-afk-round-label')),
              )
              .data,
          label,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(
                  const ValueKey<String>('planner-afk-needed-attempts'),
                ),
              )
              .data,
          attempts,
        );
        expect(find.text(ingredientCount), findsOneWidget);
      }

      expectRound('Round 1 of 3', '40 attempts', '80 x');
      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-complete-round')),
      );
      await tester.pumpAndSettle();
      expectRound('Round 2 of 3', '40 attempts', '80 x');

      final progressKey = AfkCraftProgress.sessionKeyFor(
        targetName: 'Clear Liquid Reagent',
        recipeName: 'Intermediate Reagent',
      );
      expect(
        harness.controller.active.state.value
            .afkCraftProgressFor(
              'Intermediate Reagent',
              progressKey: progressKey,
            )
            ?.completedAttempts,
        40,
      );

      await tester.tap(
        find.bySemanticsLabel('Close AFK Load for Intermediate Reagent'),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('planner-afk-round-label')),
        findsNothing,
      );
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      expectRound('Round 2 of 3', '40 attempts', '80 x');

      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-complete-round')),
      );
      await tester.pumpAndSettle();
      expectRound('Round 3 of 3', '10 attempts', '20 x');

      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-complete-round')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Plan finished'), findsOneWidget);
      expect(
        harness.controller.active.state.value
            .afkCraftProgressFor(
              'Intermediate Reagent',
              progressKey: progressKey,
            )
            ?.completedAttempts,
        90,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-undo-round')),
      );
      await tester.pumpAndSettle();
      expectRound('Round 3 of 3', '10 attempts', '20 x');

      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-complete-round')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-reset-progress')),
      );
      await tester.pumpAndSettle();
      expectRound('Round 1 of 3', '40 attempts', '80 x');
      expect(
        harness.controller.active.state.value
            .afkCraftProgressFor(
              'Intermediate Reagent',
              progressKey: progressKey,
            )
            ?.completedAttempts,
        0,
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'one-attempt labels preview quality rounding instead of dividing totals',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(
        supportingDataOverrides: const <String, Object?>{
          'itemWeightIds': <String, String>{
            'Intermediate Reagent': '1001',
            'Special Sunrise Herb': '1002',
          },
          'itemWeightsLtById': <String, double>{'1001': 2, '1002': 1},
        },
      );
      harness.controller.active.selectIngredientGrade(
        parentName: 'Intermediate Reagent',
        ingredientName: 'Sunrise Herb',
        grade: 'special',
      );
      harness.controller.updateDocument(
        (document) => document.copyWith(
          afkWeightProfile: document.afkWeightProfile.copyWith(
            maximumWeightLt: 100,
            currentCarriedWeightLt: 10,
            safetyBufferLt: 10,
          ),
        ),
        immediate: true,
      );

      await tester.pumpWidget(harness.plannerHost());
      await tester.pumpAndSettle();

      final step = harness.controller.active.plan.value.steps.firstWhere(
        (candidate) => candidate.name == 'Intermediate Reagent',
      );
      expect(step.count, 10);
      expect(step.ingredients.single.need, 4);
      final queuePerAttempt = find.byKey(
        const ValueKey<String>(
          'planner-ingredient-batch-quantity:'
          'Intermediate Reagent:Sunrise Herb',
        ),
      );
      expect(tester.widget<Text>(queuePerAttempt).data, '1');
      expect(find.text('0,4 / attempt'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey<String>(
            'planner-afk-load:alchemy:Intermediate Reagent',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final afkPerAttempt = find.byKey(
        const ValueKey<String>('planner-afk-per-attempt:Special Sunrise Herb'),
      );
      expect(afkPerAttempt, findsOneWidget);
      expect(tester.widget<Text>(afkPerAttempt).data, '1 / attempt');
      expect(find.text('4 x'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets('AFK one-attempt labels aggregate duplicate resolved stacks', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(
      supportingDataOverrides: const <String, Object?>{
        'itemWeightIds': <String, String>{
          'Intermediate Reagent': '1001',
          'Shared Blend': '1002',
        },
        'itemWeightsLtById': <String, double>{'1001': 2, '1002': 1},
      },
    );
    harness.controller.updateDocument(
      (document) => document.copyWith(
        afkWeightProfile: document.afkWeightProfile.copyWith(
          maximumWeightLt: 100,
          currentCarriedWeightLt: 10,
          safetyBufferLt: 10,
        ),
        alchemy: document.alchemy.copyWith(
          recipeEdits: <String, RecipeState?>{
            ...document.alchemy.recipeEdits,
            'Intermediate Reagent': RecipeState(
              type: 'alchemy',
              ingredients: <IngredientState>[
                IngredientState(
                  name: 'Sunrise Herb',
                  quantity: 1,
                  options: const <String>['Sunrise Herb', 'Shared Blend'],
                  substituteGroup: 'First blend',
                  substituteRatios: const <String, double>{'Shared Blend': 1},
                ),
                IngredientState(
                  name: 'Silver Azalea',
                  quantity: 2,
                  options: const <String>['Silver Azalea', 'Shared Blend'],
                  substituteGroup: 'Second blend',
                  substituteRatios: const <String, double>{'Shared Blend': 1},
                ),
              ],
            ),
            'Shared Blend': RecipeState(),
          },
          substituteChoices: const <String, String>{
            'recipe:Intermediate Reagent:First blend': 'Shared Blend',
            'recipe:Intermediate Reagent:Second blend': 'Shared Blend',
          },
        ),
      ),
      immediate: true,
    );

    await tester.pumpWidget(harness.plannerHost());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('planner-afk-load:alchemy:Intermediate Reagent'),
      ),
    );
    await tester.pumpAndSettle();

    final perAttempt = find.byKey(
      const ValueKey<String>('planner-afk-per-attempt:Shared Blend'),
    );
    expect(perAttempt, findsOneWidget);
    expect(tester.widget<Text>(perAttempt).data, '3 / attempt');
    final total = find.byKey(
      const ValueKey<String>('planner-afk-total:Shared Blend'),
    );
    expect(total, findsOneWidget);
    expect(tester.widget<Text>(total).data, '12 x');
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets('AFK Load remains usable at 130 percent text scaling', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
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
          maximumWeightLt: 100,
          currentCarriedWeightLt: 10,
          safetyBufferLt: 10,
        ),
        alchemy: document.alchemy.copyWith(want: 90),
      ),
      immediate: true,
    );

    await tester.pumpWidget(
      harness.plannerHost(
        textScaler: const TextScaler.linear(1.3),
        spec: SakuraNightGardenSpec.theme,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('planner-afk-load:alchemy:Intermediate Reagent'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('planner-afk-mode-needed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('planner-afk-complete-round')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  for (final size in const <Size>[Size(1200, 752), Size(1500, 940)]) {
    testWidgets('queue recipe squares switch the whole formula at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await setPlannerTestSize(tester, size);
      final harness = PlannerTestHarness(includeRecipeVariants: true);

      await tester.pumpWidget(
        harness.plannerHost(spec: SakuraNightGardenSpec.theme),
      );
      await tester.pumpAndSettle();

      final first = find.byKey(
        RecipeVariantSelector.choiceKey(
          'Clear Liquid Reagent',
          'reagent-route',
        ),
      );
      final second = find.byKey(
        RecipeVariantSelector.choiceKey('Clear Liquid Reagent', 'herb-route'),
      );
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(
        find.byKey(
          RecipeVariantSelector.batchChoiceKey('Clear Liquid Reagent', 1),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          RecipeVariantSelector.batchChoiceKey('Clear Liquid Reagent', 10),
        ),
        findsOneWidget,
      );
      final card = find.byWidgetPredicate(
        (widget) =>
            widget is AppSurface &&
            widget.semanticLabel == 'Clear Liquid Reagent craft step',
      );
      final nameRect = tester.getRect(
        find.byKey(PlannerActionKeys.row('P10', 'Clear Liquid Reagent')),
      );
      final methodRect = tester.getRect(
        find.descendant(of: card, matching: find.text('Residence Alchemy')),
      );
      final selectorRect = tester.getRect(
        find.descendant(of: card, matching: find.byType(RecipeVariantSelector)),
      );
      final summaryRect = tester.getRect(
        find.byKey(
          const ValueKey<String>('planner-step-summary:Clear Liquid Reagent'),
        ),
      );
      expect(methodRect.top - nameRect.bottom, greaterThanOrEqualTo(7.5));
      expect(selectorRect.top - methodRect.bottom, greaterThanOrEqualTo(11.5));
      expect(summaryRect.top - selectorRect.bottom, greaterThanOrEqualTo(9.5));
      expect(
        harness.controller.active.selectedRecipeVariantId(
          'Clear Liquid Reagent',
        ),
        'reagent-route',
      );

      await tester.tap(second);
      await tester.pumpAndSettle();

      expect(harness.controller.active.state.value.recipeVariantChoices, {
        'Clear Liquid Reagent': 'herb-route',
      });
      expect(
        harness.controller.active
            .selectedRecipe('Clear Liquid Reagent')
            ?.ingredients
            .single
            .name,
        'Silver Azalea',
      );
      expect(
        harness.controller.active.plan.value.missing
            .where((row) => row.name == 'Silver Azalea')
            .single
            .need,
        40,
      );
      await tester.tap(
        find.byKey(
          RecipeVariantSelector.batchChoiceKey('Clear Liquid Reagent', 10),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        harness.controller.active.selectedRecipeVariantId(
          'Clear Liquid Reagent',
        ),
        'herb-route-10x',
      );
      final selectedBatchQuantity = find.byKey(
        const ValueKey<String>(
          'planner-ingredient-batch-quantity:'
          'Clear Liquid Reagent:Silver Azalea',
        ),
      );
      expect(selectedBatchQuantity, findsOneWidget);
      expect(tester.widget<Text>(selectedBatchQuantity).data, '40');
      await tester.pumpWidget(
        harness.plannerHost(
          textScaler: const TextScaler.linear(1.3),
          spec: SakuraNightGardenSpec.theme,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          RecipeVariantSelector.batchChoiceKey('Clear Liquid Reagent', 10),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    });
  }

  testWidgets(
    'planner commits amount from keyboard and exposes command semantics',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final harness = PlannerTestHarness();
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(PlannerActionKeys.p01), findsOneWidget);
      expect(find.byKey(PlannerActionKeys.p02), findsOneWidget);
      expect(find.bySemanticsLabel('Alchemy Planner'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Build or recalculate plan'),
        findsOneWidget,
      );

      final amount = find.descendant(
        of: find.byKey(PlannerActionKeys.p02),
        matching: find.byType(TextField),
      );
      await tester.enterText(amount, '-2.8');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 200));
      expect(harness.controller.active.state.value.want, 1);

      await tester.tap(find.byKey(PlannerActionKeys.p05));
      await tester.tap(find.byKey(PlannerActionKeys.p03));
      await tester.pump();
      expect(
        harness.controller.active.state.value.ignoreTargetInventory,
        isFalse,
      );
      expect(harness.recipeRequests.single.context.name, 'planner');
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'owned amount survives a Windows edit-event row rebuild and Add',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();
      harness.controller.active.setIgnoreOwnedIngredients(false);
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      const name = 'Sunrise Herb';
      Finder ownedField() => find.descendant(
        of: find.byKey(PlannerActionKeys.row('P18', name)),
        matching: find.byType(TextField),
      );

      await tester.ensureVisible(ownedField());
      await tester.pump();
      final editingController = tester
          .widget<TextField>(ownedField())
          .controller!;

      // Model the vulnerable part of a Windows platform edit: EditableText's
      // controller has the new value, then its lazy list row is rebuilt before
      // a mirrored onChanged draft can become authoritative.
      editingController.value = const TextEditingValue(
        text: '1',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(
        harness.controller.active.commitInventory(name, '1000000'),
        isTrue,
      );
      await tester.pump();
      expect(ownedField(), findsNothing);

      expect(harness.controller.active.commitInventory(name, '0'), isTrue);
      await tester.pump(const Duration(milliseconds: 200));

      expect(ownedField(), findsOneWidget);
      final rebuiltController = tester
          .widget<TextField>(ownedField())
          .controller!;
      expect(rebuiltController, same(editingController));
      expect(rebuiltController.text, '1');

      await tester.tap(find.byKey(PlannerActionKeys.row('P19', name)));
      await tester.pump(const Duration(milliseconds: 200));

      expect(harness.controller.active.state.value.inventory[name], 1);
      expect(rebuiltController.text, '0');
      expect(find.text('Enter a nonnegative amount'), findsNothing);
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'target options keep icons while the selected field stays icon-free',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      Finder targetField() => find.descendant(
        of: find.byKey(PlannerActionKeys.p01),
        matching: find.byType(TextField),
      );
      void expectIconFreeSelectedField() {
        final field = tester.widget<TextField>(targetField());
        expect(field.decoration?.prefixIcon, isNull);
        expect(
          find.descendant(
            of: find.byKey(PlannerActionKeys.p01),
            matching: find.byType(PlannerItemIcon),
          ),
          findsNothing,
        );
      }

      expectIconFreeSelectedField();
      await tester.tap(targetField());
      await tester.enterText(targetField(), 'Pure Powder');
      await tester.pump();

      final choices = find.bySemanticsLabel('Craft target choices');
      expect(choices, findsOneWidget);
      final option = find.byWidgetPredicate(
        (widget) =>
            widget is AppButton &&
            widget.semanticLabel == 'Select Pure Powder Reagent',
      );
      expect(option, findsOneWidget);
      final optionIcon = tester.widget<PlannerItemIcon>(
        find.descendant(of: option, matching: find.byType(PlannerItemIcon)),
      );
      expect(optionIcon.name, 'Pure Powder Reagent');
      expect(optionIcon.size, 30);

      await tester.tap(option);
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        harness.controller.active.state.value.target,
        'Pure Powder Reagent',
      );
      expect(
        tester.widget<TextField>(targetField()).controller?.text,
        'Pure Powder Reagent',
      );
      expectIconFreeSelectedField();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is PlannerItemIcon &&
              widget.name == 'Pure Powder Reagent' &&
              widget.size == plannerStandardCommandControlHeight,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'target chooser supports arrow selection without an extra Tab stop',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      final targetHost = find.byKey(PlannerActionKeys.p01);
      final targetField = find.descendant(
        of: targetHost,
        matching: find.byType(TextField),
      );
      final keyObserver = tester.widget<Focus>(
        find.descendant(
          of: targetHost,
          matching: find.byWidgetPredicate(
            (widget) => widget is Focus && widget.onKeyEvent != null,
          ),
        ),
      );
      expect(keyObserver.skipTraversal, isTrue);
      expect(keyObserver.canRequestFocus, isFalse);

      await tester.tap(targetField);
      await tester.enterText(targetField, '');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 200));

      expect(harness.controller.active.state.value.target, "Clown's Blood");
      expect(
        tester.widget<TextField>(targetField).controller!.text,
        "Clown's Blood",
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'Sakura keeps one external target icon and real icons in target options',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();
      await tester.pumpWidget(
        harness.plannerHost(spec: SakuraNightGardenSpec.theme),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final targetHost = find.byKey(PlannerActionKeys.p01);
      final targetField = find.descendant(
        of: targetHost,
        matching: find.byType(TextField),
      );
      expect(targetField, findsOneWidget);
      expect(
        tester.widget<TextField>(targetField).decoration?.prefixIcon,
        isNull,
      );
      expect(
        find.descendant(of: targetHost, matching: find.byType(PlannerItemIcon)),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is PlannerItemIcon &&
              widget.name == 'Clear Liquid Reagent' &&
              widget.size == 54,
        ),
        findsOneWidget,
      );

      await tester.tap(targetField);
      await tester.enterText(targetField, 'Pure Powder');
      await tester.pump();
      final option = find.byWidgetPredicate(
        (widget) =>
            widget is AppButton &&
            widget.semanticLabel == 'Select Pure Powder Reagent',
      );
      expect(option, findsOneWidget);
      final optionIcon = tester.widget<PlannerItemIcon>(
        find.descendant(of: option, matching: find.byType(PlannerItemIcon)),
      );
      expect(optionIcon.name, 'Pure Powder Reagent');
      expect(optionIcon.size, 30);

      await tester.tap(option);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<TextField>(targetField).decoration?.prefixIcon,
        isNull,
      );
      expect(
        find.descendant(of: targetHost, matching: find.byType(PlannerItemIcon)),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is PlannerItemIcon &&
              widget.name == 'Pure Powder Reagent' &&
              widget.size == 54,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'queue expansion, substitute, quality, market and owned actions mutate real state',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();

      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      final firstExpansion = find.byKey(
        PlannerActionKeys.row('P09', 'Intermediate Reagent'),
      );
      expect(firstExpansion, findsOneWidget);
      expect(find.text('Hide Ingredients'), findsOneWidget);
      final perAttempt = find.byKey(
        const ValueKey<String>(
          'planner-ingredient-batch-quantity:'
          'Intermediate Reagent:Sunrise Herb',
        ),
      );
      expect(perAttempt, findsOneWidget);
      expect(tester.widget<Text>(perAttempt).data, '2');
      expect(
        tester.widget<Text>(perAttempt).style?.color,
        StandardSpec.theme.palette.text,
      );
      await tester.tap(
        find.byKey(PlannerActionKeys.row('P10', 'Intermediate Reagent')),
      );
      await tester.pump();
      expect(harness.copied, contains('Intermediate Reagent'));
      await tester.tap(firstExpansion);
      await tester.pump();
      expect(find.text('Show Ingredients'), findsNWidgets(2));
      await tester.tap(firstExpansion);
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          PlannerActionKeys.row('P11', 'Intermediate Reagent:Sunrise Herb'),
        ),
      );
      await tester.pump();
      expect(harness.copied, contains('Sunrise Herb'));

      final swap = _glyph('swap').first;
      await tester.tap(swap);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.bySemanticsLabel('Substitute choices for Sunrise Herb'),
        findsOneWidget,
      );
      expect(find.textContaining('Ratio '), findsNothing);
      expect(find.textContaining('Owned '), findsNothing);
      await tester.tap(
        find.byKey(PlannerActionKeys.row('P13', 'Silver Azalea')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        harness.controller.active.state.value.substituteChoices.values,
        contains('Silver Azalea'),
      );

      final quality = find.byKey(
        PlannerActionKeys.row('P14', 'Intermediate Reagent:Sunrise Herb'),
      );
      expect(quality, findsOneWidget);
      final swatches = find.descendant(
        of: quality,
        matching: find.byType(InkWell),
      );
      expect(swatches, findsNWidgets(3));
      await tester.tap(swatches.last);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        harness.controller.active.state.value.ingredientGrades.values,
        contains('special'),
      );

      await tester.tap(find.byKey(PlannerActionKeys.p15));
      await tester.pump(const Duration(milliseconds: 200));
      expect(harness.marketRequest, isNotNull);
      expect(
        harness.marketRequest!.namesForRefresh,
        containsAll(<String>['Sunrise Herb', 'Silver Azalea']),
        reason: 'P15 refreshes alternative candidates, not only the selection.',
      );
      expect(
        harness.controller.active.state.value.market.prices['Sunrise Herb'],
        1200,
      );
      expect(find.textContaining('2 prices refreshed'), findsOneWidget);
      await tester.tap(find.byKey(PlannerActionKeys.p16));
      await tester.pump();
      expect(
        harness.controller.active.state.value.market.prices['Sunrise Herb'],
        1200,
      );
      expect(find.byKey(PlannerActionKeys.p15), findsOneWidget);

      final owned = find.bySemanticsLabel(
        'Amount of Special Silver Azalea to add to owned inventory',
      );
      await tester.ensureVisible(owned);
      await tester.enterText(owned, '3,5');
      expect(
        harness.controller.active.state.value.inventory,
        isNot(contains('Special Silver Azalea')),
      );
      await tester.tap(
        find.byKey(PlannerActionKeys.row('P19', 'Special Silver Azalea')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        harness
            .controller
            .active
            .state
            .value
            .inventory['Special Silver Azalea'],
        3.5,
      );

      await tester.tap(
        find.byKey(PlannerActionKeys.row('P20', 'Special Silver Azalea')),
      );
      await tester.pump();
      expect(harness.copied, contains('Special Silver Azalea'));
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'quality controls use Avalonia color chips without visible grade letters',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final semantics = tester.ensureSemantics();

      for (final spec in <ThemeSpec>[
        StandardSpec.theme,
        IlluminatedLedgerSpec.theme,
      ]) {
        final harness = PlannerTestHarness();
        await tester.pumpWidget(
          MaterialApp(
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: Scaffold(
                body: PlannerView(
                  controller: harness.controller.active,
                  externalActions: harness.actions,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        final quality = find.byKey(
          PlannerActionKeys.row('P14', 'Intermediate Reagent:Sunrise Herb'),
        );
        final normal = find.descendant(
          of: quality,
          matching: find.bySemanticsLabel('Normal quality'),
        );
        final special = find.descendant(
          of: quality,
          matching: find.bySemanticsLabel('Special Grade quality'),
        );
        expect(normal, findsOneWidget);
        expect(special, findsOneWidget);
        expect(find.byTooltip('Normal'), findsOneWidget);
        expect(find.byTooltip('High Grade'), findsOneWidget);
        expect(find.byTooltip('Special Grade'), findsOneWidget);
        expect(
          find.descendant(of: quality, matching: find.byType(Text)),
          findsNothing,
        );

        final ledger = spec.family == RetainedVisualFamily.illuminatedLedger;
        expect(tester.getSize(normal), Size.square(ledger ? 26 : 24));
        final normalContainers = find.descendant(
          of: normal,
          matching: find.byType(Container),
        );
        expect(normalContainers, findsNWidgets(2));
        expect(
          tester.getSize(normalContainers.last),
          Size.square(ledger ? 12 : 16),
        );
        final normalOuter =
            tester.widget<Container>(normalContainers.first).decoration
                as BoxDecoration;
        final normalInner =
            tester.widget<Container>(normalContainers.last).decoration
                as BoxDecoration;
        expect(normalOuter.gradient, isA<LinearGradient>());
        expect(
          (normalOuter.border as Border?)?.top.color,
          ledger ? const Color(0xFFD2B15A) : const Color(0xB8FFE7A3),
        );
        expect(normalInner.color, const Color(0xAA909090));
        expect(
          (normalInner.border! as Border).top,
          BorderSide(
            color: ledger ? const Color(0xFF7C5B24) : const Color(0xFFFFF0B9),
            width: 2,
          ),
        );

        final specialContainers = find.descendant(
          of: special,
          matching: find.byType(Container),
        );
        final specialOuter =
            tester.widget<Container>(specialContainers.first).decoration
                as BoxDecoration;
        final specialInner =
            tester.widget<Container>(specialContainers.last).decoration
                as BoxDecoration;
        expect(specialOuter.gradient, isA<LinearGradient>());
        expect(
          (specialOuter.border as Border).top.color,
          ledger ? const Color(0x8A7A5B2A) : const Color(0x664E8A77),
        );
        expect(specialInner.color, const Color(0xAA558FD5));
        expect(
          (specialInner.border! as Border).top.color,
          const Color(0xB9A8C8FF),
        );

        await tester.tap(special);
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          harness.controller.active.state.value.ingredientGrades.values,
          contains('special'),
        );
        final selectedSpecialContainers = find.descendant(
          of: special,
          matching: find.byType(Container),
        );
        final selectedSpecialOuter =
            tester.widget<Container>(selectedSpecialContainers.first).decoration
                as BoxDecoration;
        final selectedSpecialInner =
            tester.widget<Container>(selectedSpecialContainers.last).decoration
                as BoxDecoration;
        expect(
          (selectedSpecialOuter.border as Border?)?.top.color,
          ledger ? const Color(0xFFD2B15A) : const Color(0xB8FFE7A3),
        );
        expect(
          (selectedSpecialInner.border! as Border).top,
          BorderSide(
            color: ledger ? const Color(0xFF7C5B24) : const Color(0xFFFFF0B9),
            width: 2,
          ),
        );
        expect(tester.takeException(), isNull);

        await harness.controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }

      semantics.dispose();
    },
  );

  testWidgets('blue quality square changes the calculated missing material', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(
      supportingDataOverrides: const <String, Object?>{
        'blueElixirMap': <String, String>{'Sunrise Herb': 'Blue Sunrise Herb'},
      },
    );
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));

    final quality = find.byKey(
      PlannerActionKeys.row('P14', 'Intermediate Reagent:Sunrise Herb'),
    );
    expect(
      find.descendant(of: quality, matching: find.byType(InkWell)),
      findsNWidgets(2),
    );
    expect(find.bySemanticsLabel('Normal quality'), findsOneWidget);
    final blue = find.bySemanticsLabel('Blue Grade quality');
    expect(blue, findsOneWidget);
    expect(
      find.byKey(PlannerActionKeys.row('P20', 'Sunrise Herb')),
      findsOneWidget,
    );

    await tester.tap(blue);
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      harness.controller.active.state.value.ingredientGrades.values,
      contains('blue'),
    );
    expect(
      find.byKey(PlannerActionKeys.row('P20', 'Sunrise Herb')),
      findsNothing,
    );
    expect(
      find.byKey(PlannerActionKeys.row('P20', 'Blue Sunrise Herb')),
      findsOneWidget,
    );
    expect(find.text('Need 7 | Have 0 | Missing 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets('processing recipes suppress ingredient quality squares', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(
      activeMode: CraftMode.processing,
      supportingDataOverrides: const <String, Object?>{
        'qualityIngredients': <String>['Wheat'],
        'qualityConversions': <String, Object?>{
          'Wheat': <String, Object?>{
            'high': <String, Object?>{'name': 'High-Quality Wheat', 'ratio': 3},
            'special': <String, Object?>{'name': 'Special Wheat', 'ratio': 5},
          },
        },
      },
    );
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(PlannerActionKeys.row('P11', 'Wheat Flour:Wheat')),
      findsOneWidget,
    );
    expect(
      find.byKey(PlannerActionKeys.row('P14', 'Wheat Flour:Wheat')),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Normal quality'), findsNothing);
    expect(find.bySemanticsLabel('High Grade quality'), findsNothing);
    expect(find.bySemanticsLabel('Special Grade quality'), findsNothing);
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets('market refresh displays row diagnostics and fetched status', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(PlannerActionKeys.p15));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('Market ID was normalized before lookup.'),
      findsOneWidget,
    );
    expect(harness.controller.active.state.value.market.region, 'eu');
    await tester.scrollUntilVisible(
      find.textContaining('Last fetched'),
      160,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey<String>('planner-need-first')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.text('Last fetched 20.07.2026, 08:00 UTC · Region EU'),
      findsOneWidget,
    );
    await harness.controller.dispose();
  });

  testWidgets('confirmed unlisted market rows hide only Central Market pills', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness(
      sunriseNpcPrice: 0,
      marketRefresh: const PlannerMarketRefresh(
        prices: <String, double>{},
        stock: <String, double>{},
        unlistedItemNames: <String>{'sunrise herb'},
        fetchedAt: 1784534400000,
        summary: 'No requested materials have market listings.',
        rowDiagnostics: <String, List<PlannerMarketRowDiagnostic>>{
          'sunrise herb': <PlannerMarketRowDiagnostic>[
            PlannerMarketRowDiagnostic(
              message: "Can't be registered on the Central Market.",
              severity: PlannerMarketDiagnosticSeverity.info,
              isMarketUnlisted: true,
            ),
          ],
        },
      ),
    );
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(PlannerActionKeys.p15));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text("Can't be registered on the Central Market."),
      findsOneWidget,
    );
    expect(find.text('Stock unknown'), findsNothing);
    expect(find.text('No price'), findsNothing);
    expect(find.text('Total -'), findsNothing);
    expect(
      harness.controller.active.state.value.market.isItemUnlisted(
        'Sunrise Herb',
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets(
    'confirmed unlisted vendor rows retain useful vendor price pills',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final harness = PlannerTestHarness(
        marketRefresh: const PlannerMarketRefresh(
          prices: <String, double>{},
          stock: <String, double>{},
          unlistedItemNames: <String>{'sunrise herb'},
          fetchedAt: 1784534400000,
          summary: 'No requested materials have market listings.',
          rowDiagnostics: <String, List<PlannerMarketRowDiagnostic>>{
            'sunrise herb': <PlannerMarketRowDiagnostic>[
              PlannerMarketRowDiagnostic(
                message: "Can't be registered on the Central Market.",
                severity: PlannerMarketDiagnosticSeverity.info,
                isMarketUnlisted: true,
              ),
            ],
          },
        ),
      );
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(PlannerActionKeys.p15));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Vendor item'), findsOneWidget);
      expect(find.text('500 each'), findsOneWidget);
      expect(find.textContaining('Total '), findsOneWidget);
      expect(find.text('Total -'), findsNothing);
      expect(find.text('Stock unknown'), findsNothing);
      expect(
        find.text("Can't be registered on the Central Market."),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'persisted unlisted status survives loading, transient failure, and hide/show',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final refresh = Completer<PlannerMarketRefresh>();
      final harness = PlannerTestHarness(
        sunriseNpcPrice: 0,
        alchemyMarket: MarketState(
          unlistedItemNames: const <String>{'  SUNRISE HERB  '},
        ),
        checkPrices: (_) => refresh.future,
      );
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text("Can't be registered on the Central Market."),
        findsNothing,
      );
      await tester.tap(find.byKey(PlannerActionKeys.p15));
      await tester.pump();

      expect(find.byKey(PlannerActionKeys.p16), findsOneWidget);
      expect(find.byKey(PlannerActionKeys.p15), findsNothing);
      expect(
        find.text("Can't be registered on the Central Market."),
        findsOneWidget,
      );
      expect(find.text('Stock unknown'), findsNothing);

      refresh.complete(
        const PlannerMarketRefresh(
          prices: <String, double>{},
          stock: <String, double>{},
          unlistedItemNames: <String>{'sunrise herb'},
          fetchedAt: 0,
          summary: 'The market check returned no usable updates.',
          rowDiagnostics: <String, List<PlannerMarketRowDiagnostic>>{
            'sunrise herb': <PlannerMarketRowDiagnostic>[
              PlannerMarketRowDiagnostic(
                message: 'The market request failed temporarily.',
                severity: PlannerMarketDiagnosticSeverity.error,
              ),
            ],
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text("Can't be registered on the Central Market."),
        findsOneWidget,
      );
      expect(
        find.text('The market request failed temporarily.'),
        findsOneWidget,
      );
      expect(
        harness.controller.active.state.value.market.isItemUnlisted(
          'Sunrise Herb',
        ),
        isTrue,
      );

      await tester.tap(find.byKey(PlannerActionKeys.p16));
      await tester.pump();
      expect(
        find.text("Can't be registered on the Central Market."),
        findsNothing,
      );
      await tester.tap(find.byKey(PlannerActionKeys.p15));
      await tester.pump();
      expect(
        find.text("Can't be registered on the Central Market."),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets('planner remains dense and overflow-free at both references', (
    tester,
  ) async {
    for (final size in <Size>[const Size(1200, 752), const Size(1500, 940)]) {
      await setPlannerTestSize(tester, size);
      final harness = PlannerTestHarness();
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Craft Queue'), findsOneWidget);
      expect(find.text('Need First'), findsOneWidget);
      expect(find.text('Residence Alchemy'), findsWidgets);
      expect(find.text('alchemy'), findsNothing);
      expect(find.byKey(PlannerActionKeys.p21), findsOneWidget);
      expect(tester.takeException(), isNull);

      await harness.controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Ledger queue and Need First scroll without visible scrollbars', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();
    final mode = harness.controller.active;
    final stepNames = List<String>.generate(
      10,
      (index) => 'Scrollable Step ${index + 1}',
    );
    mode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          'Clear Liquid Reagent': RecipeState(
            type: 'alchemy',
            baseOutput: 1,
            ingredients: <IngredientState>[
              for (final name in stepNames)
                IngredientState(
                  name: name,
                  quantity: 1,
                  options: <String>[name],
                ),
            ],
          ),
          for (final name in stepNames)
            name: RecipeState(
              type: 'alchemy',
              baseOutput: 1,
              ingredients: <IngredientState>[
                IngredientState(
                  name: '$name Material',
                  quantity: 1,
                  options: <String>['$name Material'],
                ),
              ],
            ),
        },
      ),
      immediate: true,
    );

    await tester.pumpWidget(
      harness.plannerHost(spec: IlluminatedLedgerSpec.theme),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final visibleScrollbar = find.byWidgetPredicate(
      (widget) => widget is RawScrollbar,
    );
    expect(visibleScrollbar, findsNothing);

    for (final key in const <PageStorageKey<String>>[
      PageStorageKey<String>('planner-craft-queue'),
      PageStorageKey<String>('planner-need-first'),
    ]) {
      final list = find.byKey(key);
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      expect(list, findsOneWidget);
      expect(scrollable, findsWidgets);
      final position = tester.state<ScrollableState>(scrollable.first).position;
      expect(position.maxScrollExtent, greaterThan(0));
      final before = position.pixels;

      await tester.drag(list, const Offset(0, -180));
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(before));
      expect(visibleScrollbar, findsNothing);
    }

    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets(
    'Ledger Planner preserves the Avalonia seam and full ingredient label',
    (tester) async {
      final harness = PlannerTestHarness();
      const spec = IlluminatedLedgerSpec.theme;
      for (final metrics in <({Size window, Size content})>[
        (window: Size(1500, 940), content: Size(1216, 862)),
        (window: Size(1200, 752), content: Size(916, 674)),
      ]) {
        await setPlannerTestSize(tester, metrics.window);
        await tester.pumpWidget(
          MaterialApp(
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox.fromSize(
                    size: metrics.content,
                    child: PlannerView(
                      controller: harness.controller.active,
                      externalActions: harness.actions,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        final layoutFrames = find.byWidgetPredicate(
          (widget) =>
              widget is AppSurface &&
              widget.role == AppSurfaceRole.layout &&
              (widget.semanticLabel == 'Craft Queue' ||
                  widget.semanticLabel == 'Need First'),
        );
        expect(layoutFrames, findsNWidgets(2));
        final rects = <Rect>[
          tester.getRect(layoutFrames.at(0)),
          tester.getRect(layoutFrames.at(1)),
        ]..sort((left, right) => left.left.compareTo(right.left));
        expect(
          rects.last.left - rects.first.right,
          44,
          reason: '12 px queue margin + 12 px grid spacing + 20 px Need margin',
        );
        final queueFrame = layoutFrames.at(0);
        final needFrame = layoutFrames.at(1);
        final queueHeader = find.descendant(
          of: queueFrame,
          matching: find.byType(SectionHeader),
        );
        final needHeader = find.descendant(
          of: needFrame,
          matching: find.byType(SectionHeader),
        );
        expect(queueHeader, findsOneWidget);
        expect(needHeader, findsOneWidget);
        final queueCore = find.descendant(
          of: queueHeader,
          matching: find.byKey(SectionHeader.coreKey),
        );
        final needCore = find.descendant(
          of: needHeader,
          matching: find.byKey(SectionHeader.coreKey),
        );
        expect(tester.getSize(queueCore).height, 40);
        expect(tester.getSize(needCore).height, 40);
        final resetRect = tester.getRect(find.byKey(PlannerActionKeys.p07));
        expect(resetRect.left - tester.getRect(queueCore).right, 10);
        final needHeaderWidget = tester.widget<SectionHeader>(needHeader);
        expect(needHeaderWidget.meta, isNull);
        final missingMeta = find.descendant(
          of: needHeader,
          matching: find.textContaining(' missing'),
        );
        final checkPrices = find.byKey(PlannerActionKeys.p15);
        expect(missingMeta, findsOneWidget);
        expect(
          tester.getRect(missingMeta).left - tester.getRect(needCore).right,
          10,
        );
        expect(
          tester.getRect(checkPrices).left - tester.getRect(missingMeta).right,
          10,
        );
        final commandHost = find.byWidgetPredicate(
          (widget) =>
              widget is AppSurface &&
              widget.semanticLabel == 'Planner commands',
        );
        expect(tester.getSize(commandHost).height, 96);
        expect(
          tester.widget<AppSurface>(commandHost).role,
          AppSurfaceRole.layout,
        );
        final commandMaterial = tester.widget<Container>(
          find.descendant(
            of: commandHost,
            matching: find.byKey(AppSurface.materialKey),
          ),
        );
        expect(commandMaterial.color, Colors.transparent);
        expect(commandMaterial.decoration, isNull);
        expect(
          find.descendant(
            of: commandHost,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is CustomPaint &&
                  widget.foregroundPainter is LedgerSurfaceToolingPainter,
            ),
          ),
          findsNothing,
        );

        final fullLabel = find.text('Show Ingredients');
        expect(fullLabel, findsOneWidget);
        final label = tester.widget<Text>(fullLabel);
        expect(label.style?.fontSize, 12);
        expect(label.overflow, TextOverflow.clip);
        final button = find.ancestor(
          of: fullLabel,
          matching: find.byType(AppButton),
        );
        expect(
          tester.getRect(fullLabel).width,
          lessThan(tester.getRect(button).width - 16),
        );
        expect(tester.takeException(), isNull);
      }
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'Sakura reuses Ledger planner geometry with fixed card botanicals',
    (tester) async {
      final harness = PlannerTestHarness();
      await setPlannerTestSize(tester, const Size(1500, 940));

      Future<Map<String, Rect>> capture(ThemeSpec spec) async {
        await tester.pumpWidget(harness.plannerHost(spec: spec));
        await tester.pump(const Duration(milliseconds: 200));
        final result = <String, Rect>{};
        for (final entry in <(String, Key)>[
          ('P01', PlannerActionKeys.p01),
          ('P02', PlannerActionKeys.p02),
          ('P03', PlannerActionKeys.p03),
          ('P04', PlannerActionKeys.p04),
          ('P05', PlannerActionKeys.p05),
          ('P06', PlannerActionKeys.p06),
        ]) {
          result[entry.$1] = tester.getRect(find.byKey(entry.$2));
        }
        final commandHost = find.byWidgetPredicate(
          (widget) =>
              widget is AppSurface &&
              widget.semanticLabel == 'Planner commands',
        );
        result['command'] = tester.getRect(commandHost);
        final frames = find.byWidgetPredicate(
          (widget) =>
              widget is AppSurface &&
              widget.role == AppSurfaceRole.layout &&
              (widget.semanticLabel == 'Craft Queue' ||
                  widget.semanticLabel == 'Need First'),
        );
        final frameRects = <Rect>[
          tester.getRect(frames.at(0)),
          tester.getRect(frames.at(1)),
        ]..sort((left, right) => left.left.compareTo(right.left));
        result['queue'] = frameRects.first;
        result['need'] = frameRects.last;
        final externalTargetIcon = find.byWidgetPredicate(
          (widget) =>
              widget is PlannerItemIcon &&
              widget.name == 'Clear Liquid Reagent' &&
              widget.size == 54,
        );
        result['target-icon'] = tester.getRect(externalTargetIcon);
        return result;
      }

      final ledgerGeometry = await capture(IlluminatedLedgerSpec.theme);
      final sakuraGeometry = await capture(SakuraNightGardenSpec.theme);
      expect(sakuraGeometry.keys, ledgerGeometry.keys);
      for (final key in <String>[
        'P01',
        'P02',
        'P03',
        'P04',
        'command',
        'queue',
        'need',
        'target-icon',
      ]) {
        expect(
          sakuraGeometry[key],
          ledgerGeometry[key],
          reason: '$key should retain the corrected Ledger-format fit',
        );
      }
      for (final key in <String>['P05', 'P06']) {
        expect(sakuraGeometry[key]!.right, ledgerGeometry[key]!.right);
        expect(sakuraGeometry[key]!.top, ledgerGeometry[key]!.top);
        expect(sakuraGeometry[key]!.height, 40);
      }
      expect(sakuraGeometry['need']!.left - sakuraGeometry['queue']!.right, 44);
      expect(sakuraGeometry['command']!.height, 96);
      expect(
        sakuraGeometry['queue']!.top - sakuraGeometry['command']!.bottom,
        44,
      );

      final seededCards = find.byWidgetPredicate(
        (widget) =>
            widget is AppSurface &&
            widget.role == AppSurfaceRole.card &&
            widget.ornamentIndex != null,
      );
      expect(seededCards, findsAtLeastNWidgets(2));
      final visibleSeeds = <int>{
        for (final element in seededCards.evaluate())
          (element.widget as AppSurface).ornamentIndex!,
      };
      expect(visibleSeeds, containsAll(<int>{0, 1}));
      final firstCard = seededCards.at(0);
      final firstCardSurface = tester.widget<AppSurface>(firstCard);
      final firstCardAsset = find.descendant(
        of: firstCard,
        matching: find.byType(SakuraQueueCornerAsset),
      );
      expect(firstCardAsset, findsOneWidget);
      expect(
        tester.widget<SakuraQueueCornerAsset>(firstCardAsset).variant,
        SakuraQueueCornerAsset.variantForIndex(firstCardSurface.ornamentIndex!),
      );
      expect(
        tester.getSize(firstCardAsset),
        SakuraQueueCornerAsset.authoredSize,
      );

      final intermediateCard = find.byWidgetPredicate(
        (widget) =>
            widget is AppSurface &&
            widget.semanticLabel?.startsWith(
                  'Intermediate Reagent craft step',
                ) ==
                true,
      );
      expect(intermediateCard, findsOneWidget);
      final expandedRect = tester.getRect(intermediateCard);
      final protectedQuantity = find.byKey(
        const ValueKey<String>(
          'planner-ingredient-batch-quantity:'
          'Intermediate Reagent:Sunrise Herb',
        ),
      );
      expect(protectedQuantity, findsOneWidget);
      expect(
        tester.getRect(protectedQuantity).right,
        lessThanOrEqualTo(
          expandedRect.right - SakuraQueueCornerAsset.authoredSize.width - 2,
        ),
        reason: 'Queue amounts must stay clear of the Sakura corner blossom',
      );
      final expandedAsset = find.descendant(
        of: intermediateCard,
        matching: find.byType(SakuraQueueCornerAsset),
      );
      final expandedAssetRect = tester.getRect(expandedAsset);
      expect(expandedAssetRect.size, SakuraQueueCornerAsset.authoredSize);
      expect(expandedAssetRect.right, closeTo(expandedRect.right - 1, .01));
      expect(expandedAssetRect.bottom, closeTo(expandedRect.bottom - 1, .01));
      final expandedHeight = tester.getSize(intermediateCard).height;
      final toggle = find.byKey(
        PlannerActionKeys.row('P09', 'Intermediate Reagent'),
      );
      await tester.tap(toggle);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.getSize(intermediateCard).height, lessThan(expandedHeight));
      final collapsedSurface = tester.widget<AppSurface>(intermediateCard);
      expect(collapsedSurface.ornamentIndex, isNotNull);
      final collapsedRect = tester.getRect(intermediateCard);
      final collapsedAsset = find.descendant(
        of: intermediateCard,
        matching: find.byType(SakuraQueueCornerAsset),
      );
      expect(collapsedAsset, findsOneWidget);
      final collapsedAssetRect = tester.getRect(collapsedAsset);
      expect(collapsedAssetRect.size, SakuraQueueCornerAsset.authoredSize);
      expect(collapsedAssetRect.right, closeTo(collapsedRect.right - 1, .01));
      expect(collapsedAssetRect.bottom, closeTo(collapsedRect.bottom - 1, .01));
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets('Ledger Planner fields center text at normal and 200% scale', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Centered text');
    addTearDown(controller.dispose);

    for (final scale in <double>[1, 2]) {
      final fieldHeight = scale == 1 ? 38.0 : 48.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: IlluminatedLedgerSpec.theme.materialTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ThemeSpecScope(
            spec: IlluminatedLedgerSpec.theme,
            child: StandardVisualScope(
              settings: const StandardVisualSettings(accentHue: 158),
              child: Material(
                child: Center(
                  child: SizedBox(
                    key: const ValueKey<String>('centered-planner-field'),
                    width: 260,
                    height: fieldHeight,
                    child: PlannerTextField(
                      controller: controller,
                      semanticLabel: 'Centered Planner field',
                      prefix: const Icon(Icons.search, size: 16),
                      suffix: const Icon(Icons.expand_more, size: 16),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textAlignVertical, TextAlignVertical.center);
      expect(field.decoration!.isDense, isFalse);
      final hostRect = tester.getRect(
        find.byKey(const ValueKey<String>('centered-planner-field')),
      );
      final editable = tester.allRenderObjects
          .whereType<RenderEditable>()
          .single;
      final caret = editable.getLocalRectForCaret(
        const TextPosition(offset: 1),
      );
      final caretCenter = editable.localToGlobal(caret.center).dy;
      expect(
        (caretCenter - hostRect.center.dy).abs(),
        lessThanOrEqualTo(1.5),
        reason: 'Planner text center at ${scale}x text scale',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Standard Planner command band tightly contains its controls', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness();
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));

    final commandHost = find.byWidgetPredicate(
      (widget) =>
          widget is AppSurface && widget.semanticLabel == 'Planner commands',
    );
    expect(
      tester.widget<AppSurface>(commandHost).role,
      AppSurfaceRole.commandBand,
    );
    final commandMaterial = tester.widget<Container>(
      find.descendant(
        of: commandHost,
        matching: find.byKey(AppSurface.materialKey),
      ),
    );
    final decoration = commandMaterial.decoration! as BoxDecoration;
    expect(decoration.gradient, isNotNull);
    expect(tester.getSize(commandHost).height, 82);

    final target = tester.getRect(find.byKey(PlannerActionKeys.p01));
    final recipes = tester.getRect(find.byKey(PlannerActionKeys.p03));
    final amount = tester.getRect(find.byKey(PlannerActionKeys.p02));
    final rebuild = tester.getRect(find.byKey(PlannerActionKeys.p04));
    expect(target.height, plannerStandardCommandControlHeight);
    expect(recipes.height, plannerStandardCommandControlHeight);
    expect(amount.height, plannerStandardCommandControlHeight);
    expect(rebuild.height, plannerStandardCommandControlHeight);
    expect(target.top, recipes.top);
    expect(target.bottom, recipes.bottom);
    expect(amount.top, target.top);
    expect(amount.bottom, target.bottom);
    expect(rebuild.top, target.top);
    expect(rebuild.bottom, target.bottom);

    final targetInput = tester.getRect(
      find.descendant(
        of: find.byKey(PlannerActionKeys.p01),
        matching: find.byType(TextField),
      ),
    );
    final targetGlass = tester.getRect(
      find
          .descendant(
            of: find.byKey(PlannerActionKeys.p01),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).gradient != null,
            ),
          )
          .first,
    );
    final recipesMaterial = tester.getRect(
      find.descendant(
        of: find.byKey(PlannerActionKeys.p03),
        matching: find.byKey(AppButton.materialKey),
      ),
    );
    expect(targetInput, target);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(PlannerActionKeys.p01),
              matching: find.byType(TextField),
            ),
          )
          .style!
          .fontSize,
      plannerStandardTargetFontSize,
    );
    expect(targetGlass, target);
    expect(
      _inputContainerRect(tester, find.byKey(PlannerActionKeys.p01)),
      target,
    );
    expect(
      _inputContainerRect(tester, find.byKey(PlannerActionKeys.p02)),
      amount,
    );
    expect(recipesMaterial, recipes);
    expect(
      tester.getRect(
        find.descendant(
          of: find.byKey(PlannerActionKeys.p04),
          matching: find.byKey(AppButton.materialKey),
        ),
      ),
      rebuild,
    );
    final commandRect = tester.getRect(commandHost);
    expect(commandRect.bottom - target.bottom, 7);

    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets(
    'Standard target and Recipes retain equal height in the responsive command layout',
    (tester) async {
      await setPlannerTestSize(tester, const Size(900, 700));
      final harness = PlannerTestHarness();
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      final target = tester.getRect(find.byKey(PlannerActionKeys.p01));
      final recipes = tester.getRect(find.byKey(PlannerActionKeys.p03));
      expect(target.height, plannerStandardCommandControlHeight);
      expect(recipes.height, plannerStandardCommandControlHeight);
      expect(
        tester.getRect(
          find.descendant(
            of: find.byKey(PlannerActionKeys.p01),
            matching: find.byType(TextField),
          ),
        ),
        target,
      );
      expect(
        _inputContainerRect(tester, find.byKey(PlannerActionKeys.p01)),
        target,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(PlannerActionKeys.p01),
                matching: find.byType(TextField),
              ),
            )
            .style!
            .fontSize,
        plannerStandardTargetFontSize,
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'Standard Planner paints one aligned compact command row at 1200x752',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final harness = PlannerTestHarness();
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      final target = tester.getRect(find.byKey(PlannerActionKeys.p01));
      final recipes = tester.getRect(find.byKey(PlannerActionKeys.p03));
      final amount = tester.getRect(find.byKey(PlannerActionKeys.p02));
      final rebuild = tester.getRect(find.byKey(PlannerActionKeys.p04));
      for (final rect in <Rect>[target, recipes, amount, rebuild]) {
        expect(rect.height, plannerStandardCommandControlHeight);
        expect(rect.top, target.top);
        expect(rect.bottom, target.bottom);
      }
      expect(
        _inputContainerRect(tester, find.byKey(PlannerActionKeys.p01)),
        target,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(PlannerActionKeys.p01),
                matching: find.byType(TextField),
              ),
            )
            .style!
            .fontSize,
        plannerStandardTargetFontSize,
      );
      expect(
        _inputContainerRect(tester, find.byKey(PlannerActionKeys.p02)),
        amount,
      );
      for (final action in <Key>[
        PlannerActionKeys.p03,
        PlannerActionKeys.p04,
      ]) {
        expect(
          tester.getRect(
            find.descendant(
              of: find.byKey(action),
              matching: find.byKey(AppButton.materialKey),
            ),
          ),
          tester.getRect(find.byKey(action)),
        );
      }
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets('wide Standard rows preserve Avalonia grid geometry', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness();
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));

    final targetField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(PlannerActionKeys.p01),
        matching: find.byType(TextField),
      ),
    );
    expect(targetField.textAlignVertical, TextAlignVertical.center);
    expect(
      targetField.decoration!.contentPadding,
      const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    );
    expect(targetField.decoration!.prefixIcon, isNull);
    expect(targetField.style!.fontSize, plannerStandardTargetFontSize);
    expect(targetField.style!.fontWeight, FontWeight.w700);
    expect(
      find.descendant(
        of: find.byKey(PlannerActionKeys.p01),
        matching: find.byType(PlannerItemIcon),
      ),
      findsNothing,
    );

    final queueIcon = tester.getRect(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is PlannerItemIcon &&
                widget.name == 'Intermediate Reagent',
          )
          .first,
    );
    final queueName = tester.getRect(
      find.byKey(PlannerActionKeys.row('P10', 'Intermediate Reagent')),
    );
    final expandedQueueCard = find
        .ancestor(
          of: find.byKey(PlannerActionKeys.row('P10', 'Intermediate Reagent')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AppSurface && widget.role == AppSurfaceRole.card,
          ),
        )
        .first;
    final collapsedQueueCard = find
        .ancestor(
          of: find.byKey(PlannerActionKeys.row('P10', 'Clear Liquid Reagent')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AppSurface && widget.role == AppSurfaceRole.card,
          ),
        )
        .first;
    final completion = tester.getRect(
      find.byKey(PlannerActionKeys.row('P08', 'Intermediate Reagent')),
    );
    expect(queueIcon.size, const Size.square(54));
    expect(queueName.left - queueIcon.right, 14);
    expect(completion.size, const Size.square(48));
    expect(completion.center.dy, closeTo(queueIcon.center.dy, .01));
    expect(tester.getSize(expandedQueueCard).height, 234);
    expect(tester.getSize(collapsedQueueCard).height, 170);

    final queueIngredientName = tester.getRect(
      find.byKey(
        PlannerActionKeys.row('P11', 'Intermediate Reagent:Sunrise Herb'),
      ),
    );
    final queueSubstitute = tester.getRect(
      find.byKey(
        PlannerActionKeys.row('P12', 'step:Intermediate Reagent:Wild Herbs'),
      ),
    );
    final queueQuality = tester.getRect(
      find.byKey(
        PlannerActionKeys.row('P14', 'Intermediate Reagent:Sunrise Herb'),
      ),
    );
    expect(queueSubstitute.left - queueIngredientName.right, 6);
    expect(queueQuality.left - queueSubstitute.right, 6);
    expect(
      queueSubstitute.center.dy,
      closeTo(queueIngredientName.center.dy, .01),
    );
    expect(queueQuality.center.dy, closeTo(queueIngredientName.center.dy, .01));

    const missingName = 'Sunrise Herb';
    final ownedActions = find.byKey(PlannerActionKeys.row('P18', missingName));
    await tester.ensureVisible(ownedActions);
    await tester.pump();
    final ownedField = tester.getRect(
      find.descendant(of: ownedActions, matching: find.byType(TextField)),
    );
    final add = tester.getRect(
      find.byKey(PlannerActionKeys.row('P19', missingName)),
    );
    final needNameFinder = find.byKey(
      PlannerActionKeys.row('P20', missingName),
    );
    final needSurface = find
        .ancestor(
          of: needNameFinder,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AppSurface && widget.role == AppSurfaceRole.row,
          ),
        )
        .first;
    final needIcon = tester.getRect(
      find
          .descendant(
            of: needSurface,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is PlannerItemIcon && widget.name == missingName,
            ),
          )
          .first,
    );
    final needName = tester.getRect(needNameFinder);
    final needSubstitute = tester.getRect(
      find.byKey(
        PlannerActionKeys.row('P12', 'missing:Sunrise Herb:Wild Herbs'),
      ),
    );
    final needSource = tester.getRect(
      find.byKey(PlannerActionKeys.row('P17', missingName)),
    );
    expect(ownedField.size, const Size(82, 38));
    expect(add.left - ownedField.right, 15);
    expect(needIcon.size, const Size.square(50));
    expect(needName.left - needIcon.right, 12);
    expect(needSubstitute.left - needName.right, 5);
    expect(needSource.left - needSubstitute.right, 5);
    expect(needSubstitute.center.dy, closeTo(needName.center.dy, .01));
    expect(needSource.center.dy, closeTo(needName.center.dy, .01));
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets('wide command toggles are clickable through their lower edge', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness();
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));

    final action = find.byKey(PlannerActionKeys.p06);
    final before =
        harness.controller.active.state.value.ignoreIngredientInventory;
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harness.controller.active.state.value.ignoreIngredientInventory,
      isNot(before),
    );
    final rect = tester.getRect(action);
    final point = Offset(rect.center.dx, rect.bottom - 2);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      harness.controller.active.state.value.ignoreIngredientInventory,
      before,
    );
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets('Standard command toggles hug their marker and label', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness();
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));

    final fullTarget = find.byKey(PlannerActionKeys.p05);
    final ignoreOwned = find.byKey(PlannerActionKeys.p06);
    final fullRect = tester.getRect(fullTarget);
    final ignoreRect = tester.getRect(ignoreOwned);
    expect(fullRect.height, 32);
    expect(ignoreRect.height, 32);
    expect(fullRect.width, lessThan(350));
    expect(ignoreRect.width, lessThan(380));
    expect(ignoreRect.width, greaterThan(fullRect.width));

    final marker = find.descendant(
      of: fullTarget,
      matching: find.byKey(PlannerToggle.standardMarkerKey),
    );
    final label = find.descendant(
      of: fullTarget,
      matching: find.text('FULL TARGET AMOUNT'),
    );
    final markerRect = tester.getRect(marker);
    final labelRect = tester.getRect(label);
    expect(markerRect.size, const Size.square(20));
    expect(markerRect.left - fullRect.left, closeTo(10, .01));
    expect(labelRect.left - markerRect.right, closeTo(7, .01));
    expect(fullRect.right - labelRect.right, closeTo(10, .01));
    expect(markerRect.center.dy, closeTo(labelRect.center.dy, .01));
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: marker, matching: find.byIcon(Icons.check)),
          )
          .size,
      12,
    );
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets(
    'P22 queue and Need First acquisition is click-only and dismisses without mutation',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final harness = PlannerTestHarness();
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));
      final before = harness.controller.active.state.value.toJson();
      final action = find.byKey(
        PlannerActionKeys.row('P22', 'Intermediate Reagent:Sunrise Herb'),
      );
      final card = find.bySemanticsLabel('How to obtain Sunrise Herb');
      expect(action, findsOneWidget);
      expect(card, findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(action));
      await tester.pump(const Duration(milliseconds: 500));
      expect(card, findsNothing);

      final substitute = find.byKey(
        PlannerActionKeys.row('P12', 'step:Intermediate Reagent:Wild Herbs'),
      );
      await tester.tap(substitute);
      await tester.pump();
      expect(
        find.bySemanticsLabel('Substitute choices for Sunrise Herb'),
        findsOneWidget,
      );

      await tester.tap(action);
      await tester.pump();
      expect(
        find.bySemanticsLabel('Substitute choices for Sunrise Herb'),
        findsNothing,
      );
      expect(card, findsOneWidget);
      final acquisitionDrag = find.byKey(
        const ValueKey<String>(
          'planner-acquisition-drag-region:'
          'Intermediate Reagent:Sunrise Herb',
        ),
      );
      expect(acquisitionDrag, findsOneWidget);
      expect(
        find.descendant(
          of: acquisitionDrag,
          matching: find.bySemanticsLabel(
            'Close acquisition information for Sunrise Herb',
          ),
        ),
        findsNothing,
      );
      _expectInsideViewport(tester.getRect(card), const Size(1200, 752));
      expect(find.text('How to Obtain'), findsOneWidget);
      expect(find.text('Gathered near Heidel roads.'), findsOneWidget);
      expect(find.text('Gathering.'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(card, findsNothing);

      await tester.tap(action);
      await tester.pump();
      expect(card, findsOneWidget);
      await tester.tap(
        find.bySemanticsLabel('Close acquisition information for Sunrise Herb'),
      );
      await tester.pump();
      expect(card, findsNothing);

      await tester.tap(action);
      await tester.pump();
      expect(card, findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(card, findsNothing);

      final needSubstitute = find.byKey(
        PlannerActionKeys.row('P12', 'missing:Sunrise Herb:Wild Herbs'),
      );
      final needAction = find.byKey(
        PlannerActionKeys.row('P22', 'need:Sunrise Herb'),
      );
      expect(needAction, findsOneWidget);
      await tester.tap(needSubstitute);
      await tester.pump();
      expect(
        find.bySemanticsLabel('Substitute choices for Sunrise Herb'),
        findsOneWidget,
      );

      await tester.tap(needAction);
      await tester.pump();
      expect(
        find.bySemanticsLabel('Substitute choices for Sunrise Herb'),
        findsNothing,
      );
      expect(card, findsOneWidget);
      _expectInsideViewport(tester.getRect(card), const Size(1200, 752));
      expect(find.text('Gathered near Heidel roads.'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(card, findsNothing);
      expect(harness.controller.active.state.value.toJson(), before);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      semantics.dispose();
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'P17 is a compact beside annotation closed by X or outside, not Escape',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final harness = PlannerTestHarness();
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));
      final before = harness.controller.active.state.value.toJson();

      await tester.tap(_glyph('swap').first);
      await tester.pump();
      final substitute = find.bySemanticsLabel(
        'Substitute choices for Sunrise Herb',
      );
      expect(substitute, findsOneWidget);
      _expectInsideViewport(tester.getRect(substitute), const Size(1200, 752));

      final sourceAction = find.byKey(
        PlannerActionKeys.row('P17', 'Sunrise Herb'),
      );
      expect(sourceAction, findsOneWidget);
      await tester.tap(sourceAction);
      await tester.pump();
      expect(substitute, findsOneWidget);
      final source = find.bySemanticsLabel(
        'Source information for Sunrise Herb',
      );
      expect(source, findsOneWidget);
      final sourceDrag = find.byKey(
        const ValueKey<String>('planner-source-info-drag-region'),
      );
      expect(sourceDrag, findsOneWidget);
      expect(
        find.descendant(
          of: sourceDrag,
          matching: find.bySemanticsLabel(
            'Close source information for Sunrise Herb',
          ),
        ),
        findsNothing,
      );
      _expectInsideViewport(tester.getRect(source), const Size(1200, 752));
      expect(tester.getSize(source).width, 330);
      expect(
        find.text(
          'Gathered near Heidel roads.\n'
          'Vendor: Material Vendor - Heidel',
        ),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(source, findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(source, findsNothing);
      expect(substitute, findsOneWidget);

      await tester.tap(_glyph('swap').first);
      await tester.pump();
      expect(substitute, findsNothing);

      await tester.tap(sourceAction);
      await tester.pump();
      expect(source, findsOneWidget);
      await tester.tap(
        find.bySemanticsLabel('Close source information for Sunrise Herb'),
      );
      await tester.pump();
      expect(source, findsNothing);
      expect(harness.controller.active.state.value.toJson(), before);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await harness.controller.dispose();
    },
  );

  testWidgets('Ledger P17 matches the retained 330 px annotation card', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness();
    const spec = IlluminatedLedgerSpec.theme;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      AppOverlayCoordinatorHost(
        child: MaterialApp(
          theme: spec.materialTheme(),
          home: ThemeSpecScope(
            spec: spec,
            child: Scaffold(
              body: PlannerView(
                controller: harness.controller.active,
                externalActions: harness.actions,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final sourceAction = find.byKey(
      PlannerActionKeys.row('P17', 'Sunrise Herb'),
    );
    await tester.tap(sourceAction);
    await tester.pump();
    final source = find.bySemanticsLabel('Source information for Sunrise Herb');
    expect(source, findsOneWidget);
    final sourceRect = tester.getRect(source);
    final anchorRect = tester.getRect(sourceAction);
    final bodyRect = tester.getRect(
      find.byKey(const ValueKey<String>('planner-source-info-body')),
    );
    expect(sourceRect.width, 330);
    expect(
      sourceRect.height,
      closeTo(bodyRect.height + 61, .01),
      reason: '9 top + 34 header + 6 gap + body + 10 bottom + borders',
    );
    expect(sourceRect.left - anchorRect.right, 6);
    expect(sourceRect.center.dy, closeTo(anchorRect.center.dy, .01));

    final icon = tester.widget<PlannerItemIcon>(
      find
          .descendant(
            of: source,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is PlannerItemIcon && widget.name == 'Sunrise Herb',
            ),
          )
          .first,
    );
    expect(icon.size, 34);
    expect(
      tester.getSize(
        find.bySemanticsLabel('Close source information for Sunrise Herb'),
      ),
      const Size.square(30),
    );
    final body = tester.widget<Text>(
      find.byKey(const ValueKey<String>('planner-source-info-body')),
    );
    expect(body.style?.color, const Color(0xFF65543F));
    expect(body.style?.fontFamily, 'Georgia');
    expect(body.style?.fontSize, 12);
    expect(body.style?.fontWeight, FontWeight.w600);
    final surface = tester.widget<Container>(
      find.byKey(const ValueKey<String>('planner-source-info-card')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, const <Color>[
      Color.fromARGB(249, 255, 247, 223),
      Color.fromARGB(168, 231, 211, 171),
    ]);
    expect(
      find.descendant(
        of: source,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is LedgerOrnamentFramePainter,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.bySemanticsLabel('Close source information for Sunrise Herb'),
    );
    await tester.pump();
    expect(source, findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await harness.controller.dispose();
  });

  testWidgets(
    'Ledger substitute chooser expands inline as a two-column authored grid',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();
      const spec = IlluminatedLedgerSpec.theme;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        AppOverlayCoordinatorHost(
          child: MaterialApp(
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: Scaffold(
                body: PlannerView(
                  controller: harness.controller.active,
                  externalActions: harness.actions,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final toggle = find.byKey(
        PlannerActionKeys.row('P12', 'missing:Sunrise Herb:Wild Herbs'),
      );
      expect(toggle, findsOneWidget);
      expect(tester.getSize(toggle), const Size(28, 28));
      final queueName = find.byKey(
        PlannerActionKeys.row('P10', 'Intermediate Reagent'),
      );
      final queueTopBefore = tester.getTopLeft(queueName).dy;
      final needName = find.byKey(PlannerActionKeys.row('P20', 'Sunrise Herb'));
      final needSurface = find
          .ancestor(
            of: needName,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is AppSurface && widget.role == AppSurfaceRole.row,
            ),
          )
          .first;

      await tester.tap(toggle);
      await tester.pump();
      await tester.pump();
      final chooser = find.bySemanticsLabel(
        'Substitute choices for Sunrise Herb',
      );
      expect(chooser, findsOneWidget);
      expect(tester.getTopLeft(queueName).dy, queueTopBefore);
      final chooserRect = tester.getRect(chooser);
      final needRect = tester.getRect(needSurface);
      expect(chooserRect.left - needRect.left, closeTo(63, .01));
      expect(needRect.right - chooserRect.right, closeTo(11, .01));

      final first = find.byKey(PlannerActionKeys.row('P13', 'Sunrise Herb'));
      final second = find.byKey(PlannerActionKeys.row('P13', 'Silver Azalea'));
      expect(tester.getSize(first), const Size(174, 52));
      expect(tester.getSize(second), const Size(174, 52));
      final firstRect = tester.getRect(first);
      final secondRect = tester.getRect(second);
      expect(secondRect.left - firstRect.right, 6);
      expect(secondRect.top, firstRect.top);
      expect(
        tester
            .widget<PlannerItemIcon>(
              find
                  .descendant(of: first, matching: find.byType(PlannerItemIcon))
                  .first,
            )
            .size,
        26,
      );
      expect(find.text('Choose Substitute'), findsNothing);
      expect(find.textContaining('Ratio '), findsNothing);
      expect(find.textContaining('Owned '), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(chooser, findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(chooser, findsOneWidget);

      await tester.tap(toggle);
      await tester.pump();
      expect(chooser, findsNothing);
      await tester.tap(toggle);
      await tester.pump();
      await tester.tap(second);
      await tester.pump(const Duration(milliseconds: 200));
      expect(chooser, findsNothing);
      expect(
        harness.controller.active.state.value.substituteChoices.values,
        contains('Silver Azalea'),
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await harness.controller.dispose();
    },
  );

  testWidgets('P08 uses Ledger wax without changing its domain command', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness();
    const spec = IlluminatedLedgerSpec.theme;
    await tester.pumpWidget(
      MaterialApp(
        theme: spec.materialTheme(),
        home: ThemeSpecScope(
          spec: spec,
          child: Scaffold(
            body: PlannerView(
              controller: harness.controller.active,
              externalActions: harness.actions,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester.widget<AppButton>(find.byKey(PlannerActionKeys.p03)).role,
      AppButtonRole.primary,
    );
    expect(
      tester.widget<AppButton>(find.byKey(PlannerActionKeys.p04)).role,
      AppButtonRole.primary,
    );
    expect(
      tester.widget<AppButton>(find.byKey(PlannerActionKeys.p05)).role,
      AppButtonRole.optionPill,
    );
    expect(
      tester.widget<AppButton>(find.byKey(PlannerActionKeys.p07)).role,
      AppButtonRole.primary,
    );

    final action = find.byKey(
      PlannerActionKeys.row('P08', 'Intermediate Reagent'),
    );
    expect(action, findsOneWidget);
    expect(
      find.descendant(
        of: action,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is LedgerWaxSealPainter,
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      harness.controller.active.state.value.completedSteps,
      contains('Intermediate Reagent'),
    );
    await harness.controller.dispose();
  });

  testWidgets(
    'completing the target hides every completed queue row and shows both empty states',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();

      await tester.pumpWidget(harness.plannerHost());
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(PlannerActionKeys.row('P08', 'Clear Liquid Reagent')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(PlannerActionKeys.row('P08', 'Clear Liquid Reagent')),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        harness.controller.active.state.value.completedSteps,
        contains('Clear Liquid Reagent'),
      );
      expect(find.text('0 left'), findsOneWidget);
      expect(find.text('0 missing'), findsOneWidget);
      expect(
        find.byKey(PlannerActionKeys.row('P08', 'Clear Liquid Reagent')),
        findsNothing,
      );
      expect(
        find.byKey(PlannerActionKeys.row('P08', 'Intermediate Reagent')),
        findsNothing,
      );
      expect(
        find.text(
          'No craft steps are needed for the current target and inventory.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'All base materials are covered by inventory or craft steps.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets('Reset restores the queue after target completion', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness();

    await tester.pumpWidget(harness.plannerHost());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(
      find.byKey(PlannerActionKeys.row('P08', 'Clear Liquid Reagent')),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(PlannerActionKeys.p07));
    await tester.pump(const Duration(milliseconds: 200));

    expect(harness.controller.active.state.value.completedSteps, isEmpty);
    expect(find.text('2 left'), findsOneWidget);
    expect(find.text('1 missing'), findsOneWidget);
    expect(
      find.byKey(PlannerActionKeys.row('P08', 'Clear Liquid Reagent')),
      findsOneWidget,
    );
    expect(
      find.byKey(PlannerActionKeys.row('P08', 'Intermediate Reagent')),
      findsOneWidget,
    );
    expect(
      find.text(
        'No craft steps are needed for the current target and inventory.',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets(
    'saved custom icons and aliases reach planner, recipe, and Need First rows',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final stored = (await tester.runAsync(StoredIconTestFixture.create))!;
      addTearDown(() => tester.runAsync(stored.dispose));
      final harness = PlannerTestHarness(
        alchemyIconDataUris: const <String, String>{
          'Silver Azalea': customIconTestDataUri,
        },
      );
      harness.controller.active.updateState(
        (state) => state.copyWith(
          customIcons: <String, CustomIconReference>{
            'Clear Liquid Reagent': stored.reference,
            'Intermediate Reagent': stored.reference,
          },
          iconAliases: const <String, String>{'Sunrise Herb': 'Silver Azalea'},
        ),
        immediate: true,
      );

      await tester.pumpWidget(harness.plannerHost(iconStore: stored.store));
      await tester.pump(const Duration(milliseconds: 220));

      final targetImage = find.byKey(
        ModeItemIconKeys.image('Clear Liquid Reagent'),
      );
      await pumpUntilIconState(tester, targetImage);
      expect(targetImage, findsWidgets);
      final target = tester.widget<Image>(targetImage.first);
      expect(target.image, isA<MemoryImage>());
      expect((target.image as MemoryImage).bytes, orderedEquals(stored.bytes));

      final recipeCard = find
          .ancestor(
            of: find.byKey(
              PlannerActionKeys.row('P10', 'Intermediate Reagent'),
            ),
            matching: find.byType(AppSurface),
          )
          .first;
      expect(
        find.descendant(
          of: recipeCard,
          matching: find.byKey(ModeItemIconKeys.image('Intermediate Reagent')),
        ),
        findsOneWidget,
      );

      final needFirstRow = find
          .ancestor(
            of: find.byKey(PlannerActionKeys.row('P20', 'Sunrise Herb')),
            matching: find.byType(AppSurface),
          )
          .first;
      expect(
        find.descendant(
          of: needFirstRow,
          matching: find.byKey(ModeItemIconKeys.image('Sunrise Herb')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: needFirstRow,
          matching: find.byKey(ModeItemIconKeys.failure('Sunrise Herb')),
        ),
        findsNothing,
      );

      await tester.runAsync(() => stored.store.remove(stored.reference));
      harness.controller.active.updateState(
        (state) => state.copyWith(want: state.want + 1),
        immediate: true,
      );
      await tester.pump(const Duration(milliseconds: 220));
      final missing = find.descendant(
        of: recipeCard,
        matching: find.byKey(ModeItemIconKeys.failure('Intermediate Reagent')),
      );
      await pumpUntilIconState(tester, missing);
      expect(missing, findsOneWidget);
      final failureTooltip = tester.widget<Tooltip>(
        find.descendant(of: missing, matching: find.byType(Tooltip)),
      );
      expect(failureTooltip.message, contains('invalid or missing'));

      await harness.controller.dispose();
    },
  );
}

void _expectInsideViewport(Rect rect, Size viewport) {
  expect(rect.left, greaterThanOrEqualTo(12));
  expect(rect.top, greaterThanOrEqualTo(12));
  expect(rect.right, lessThanOrEqualTo(viewport.width - 12));
  expect(rect.bottom, lessThanOrEqualTo(viewport.height - 12));
}

Finder _glyph(String name) => find.byWidgetPredicate(
  (widget) => widget is AppVectorGlyph && widget.name == name,
);

Rect _inputContainerRect(WidgetTester tester, Finder fieldAncestor) {
  final editable = find.descendant(
    of: fieldAncestor,
    matching: find.byType(EditableText),
  );
  final container = InputDecorator.containerOf(tester.element(editable))!;
  return container.localToGlobal(Offset.zero) & container.size;
}
