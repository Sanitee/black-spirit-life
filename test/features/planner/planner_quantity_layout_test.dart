import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_quantity_layout.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/features/shared/workshop_presentation.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import 'planner_test_fixture.dart';

const _removedToggleKey = ValueKey('planner-readability-preview-toggle');
const _themes = <ThemeSpec>[
  SakuraNightGardenSpec.theme,
  IlluminatedLedgerSpec.theme,
  StandardSpec.theme,
];

Finder _summary(String name) =>
    find.byKey(ValueKey('planner-step-summary:$name'));

Finder _needQuantity(String stableId, String label) =>
    find.byKey(ValueKey('planner-need-quantity:$stableId:$label'));

Finder _quantity(String recipe, String ingredient, {bool perCraft = false}) =>
    find.byKey(
      ValueKey(
        'planner-ingredient-${perCraft ? 'per-craft' : 'batch'}-quantity:'
        '$recipe:$ingredient',
      ),
    );

void main() {
  testWidgets(
    'quantity layout is default across modes, themes, navigation, and reload without extra saves',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final semantics = tester.ensureSemantics();
      final harness = PlannerTestHarness();
      addTearDown(harness.controller.dispose);
      var saves = 0;
      final application = PlannerApplicationController(
        catalog: harness.controller.catalog,
        initialState: harness.controller.documentSnapshot,
        saveState: (state) async {
          saves += 1;
          return state;
        },
        saveDebounce: Duration.zero,
      );
      addTearDown(application.dispose);
      const codec = PlannerStateJsonCodec();
      for (final mode in CraftMode.values) {
        application.switchMode(mode);
        await application.flush();
        final originalDocument = codec.encode(application.documentSnapshot);
        final originalPlan = jsonEncode(application.active.plan.value.toJson());
        final originalSaves = saves;
        if (mode == CraftMode.alchemy) expect(originalSaves, 0);
        final step = application.active.plan.value.steps.first;
        final ingredient = step.ingredients.single.original;
        for (final spec in _themes) {
          await tester.pumpWidget(
            _host(harness, application: application, spec: spec),
          );
          await tester.pumpAndSettle();
          _expectNoTrialControls();
          _expectNoBroadRedesign();
          _expectMatchingQuantityBadges(
            tester,
            _quantity(step.name, ingredient, perCraft: true),
            _quantity(step.name, ingredient),
            spec: spec,
          );
          _expectNeedQuantities(
            tester,
            application.active.plan.value.missing.single,
            spec: spec,
          );
          _expectSummary(
            tester,
            step,
            processing: mode == CraftMode.processing,
          );
          await application.flush();
          expect(codec.encode(application.documentSnapshot), originalDocument);
          expect(
            jsonEncode(application.active.plan.value.toJson()),
            originalPlan,
          );
          expect(saves, originalSaves);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(_host(harness, application: application));
        await tester.pumpAndSettle();
        _expectNoTrialControls();
        _expectMatchingQuantityBadges(
          tester,
          _quantity(step.name, ingredient, perCraft: true),
          _quantity(step.name, ingredient),
        );

        var reloadSaves = 0;
        final reloaded = PlannerApplicationController(
          catalog: application.catalog,
          initialState: codec.decode(originalDocument),
          saveState: (state) async {
            reloadSaves += 1;
            return state;
          },
          saveDebounce: Duration.zero,
        );
        addTearDown(reloaded.dispose);
        await tester.pumpWidget(_host(harness, application: reloaded));
        await tester.pumpAndSettle();
        _expectNoTrialControls();
        _expectMatchingQuantityBadges(
          tester,
          _quantity(step.name, ingredient, perCraft: true),
          _quantity(step.name, ingredient),
        );
        _expectNeedQuantities(
          tester,
          reloaded.active.plan.value.missing.single,
        );
        await reloaded.flush();
        expect(jsonEncode(reloaded.active.plan.value.toJson()), originalPlan);
        expect(codec.encode(reloaded.documentSnapshot), originalDocument);
        expect(reloadSaves, 0);
      }

      await tester.pumpWidget(harness.bonusHost());
      await tester.pumpAndSettle();
      _expectNoTrialControls();
      expect(find.byType(PlannerNeedQuantities), findsWidgets);
      expect(
        tester
            .widget<Text>(
              _quantity('Intermediate Reagent', 'Sunrise Herb', perCraft: true),
            )
            .style
            ?.fontSize,
        13,
      );
      _expectOriginalTotalColumn(
        tester,
        _quantity('Intermediate Reagent', 'Sunrise Herb'),
      );
      expect(
        find.byKey(const ValueKey('planner-step-summary:Intermediate Reagent')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final spec in _themes) {
    testWidgets(
      'B keeps the compact quantity line in the header in ${spec.id}',
      (tester) async {
        await setPlannerTestSize(tester, const Size(1500, 940));
        final harness = PlannerTestHarness();
        addTearDown(harness.controller.dispose);
        await tester.pumpWidget(
          _host(harness, spec: spec, size: const Size(1500, 940)),
        );
        await tester.pumpAndSettle();
        final step = harness.controller.active.plan.value.steps.first;
        final card = find.byKey(ValueKey('queue:${step.name}'));
        final header = find.byKey(
          ValueKey('planner-queue-heading:${step.name}'),
        );
        final summary = _summary(step.name);
        _expectSummary(tester, step);
        final fields = [
          for (final label in ['Craft', 'Results', 'Need'])
            tester.getRect(
              find.byKey(ValueKey('planner-craft-field:${step.name}:$label')),
            ),
        ];
        expect(fields[1].top, closeTo(fields[0].top, .01));
        expect(fields[2].top, closeTo(fields[0].top, .01));
        expect(fields[1].left - fields[0].right, closeTo(8, .01));
        expect(fields[2].left - fields[1].right, closeTo(8, .01));
        final method = find.descendant(
          of: header,
          matching: find.text('Residence Alchemy'),
        );
        expect(
          tester.getRect(summary).top - tester.getRect(method).bottom,
          // The 12 px gap starts after the pill, whose text inset is themed.
          inInclusiveRange(12, 18),
        );
        final divider = find
            .descendant(of: card, matching: find.byType(WorkshopSectionRule))
            .first;
        expect(
          tester.getRect(divider).top,
          greaterThanOrEqualTo(tester.getRect(header).bottom + 11.9),
        );
        final summaryBefore = tester.getRect(summary);
        final heightBefore = tester.getSize(card).height;
        final planBefore = jsonEncode(
          harness.controller.active.plan.value.toJson(),
        );
        await _tap(tester, find.byKey(PlannerActionKeys.row('P09', step.name)));
        expect(tester.getRect(summary), summaryBefore);
        expect(tester.getSize(card).height, lessThan(heightBefore));
        expect(
          jsonEncode(harness.controller.active.plan.value.toJson()),
          planBefore,
        );
        expect(tester.takeException(), isNull);
      },
    );
    for (final size in const [Size(916, 674), Size(1216, 862)]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'default quantities ${spec.id} at $size and ${scale}x text keep long rows readable',
          (tester) async {
            await setPlannerTestSize(tester, const Size(1500, 940));
            final harness = PlannerTestHarness(
              includeLightstoneNeed: true,
              supportingDataOverrides: const {
                'marketIds': {'Imperfect Lightstone of Flora': '999001'},
              },
            );
            addTearDown(harness.controller.dispose);
            harness.controller.active.commitAmount('13709');
            harness.controller.active.replaceMarketValues(
              prices: const {'Imperfect Lightstone of Flora': 1200},
              stock: const {'Imperfect Lightstone of Flora': 0},
              unlistedItemNames: const [],
              fetchedAt: 1784534400000,
            );
            harness.controller.active.setPricesVisible(true);
            await tester.pumpWidget(
              _host(harness, spec: spec, size: size, scale: scale),
            );
            await tester.pumpAndSettle();
            const recipe = 'Purified Lightstone of Flora';
            const ingredient = 'Imperfect Lightstone of Flora';
            _expectSummary(
              tester,
              harness.controller.active.plan.value.steps.single,
            );
            final formula = _quantity(recipe, ingredient, perCraft: true);
            final total = _quantity(recipe, ingredient);
            expect(tester.widget<Text>(formula).data, 'x4');
            expect(tester.widget<Text>(formula).style?.fontSize, 16);
            expect(
              tester.widget<Text>(formula).style?.fontWeight,
              FontWeight.w600,
            );
            expect(tester.widget<Text>(total).data, '54.836');
            _expectMatchingQuantityBadges(
              tester,
              formula,
              total,
              spec: spec,
              scale: scale,
            );
            _expectNeedQuantities(
              tester,
              harness.controller.active.plan.value.missing.single,
              spec: spec,
            );
            final needRow = find.byType(PlannerNeedQuantities).first;
            for (final detail in [
              find.text('Out of stock'),
              find.text('1.200 each'),
            ]) {
              final bounds = tester.getRect(
                find.descendant(of: needRow, matching: detail),
              );
              expect(
                bounds.left,
                greaterThanOrEqualTo(tester.getRect(needRow).left),
              );
              expect(
                bounds.right,
                lessThanOrEqualTo(tester.getRect(needRow).right + .01),
              );
            }
            _expectNoBroadRedesign();
            expect(
              tester.getRect(formula).overlaps(tester.getRect(total)),
              isFalse,
            );
            expect(find.byType(Scrollbar), findsNothing);
            expect(find.byType(RawScrollbar), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final mode in CraftMode.values) {
    testWidgets(
      'default ${mode.name} quantities follow target and owned changes',
      (tester) async {
        await setPlannerTestSize(tester, const Size(1500, 940));
        final harness = PlannerTestHarness(activeMode: mode);
        addTearDown(harness.controller.dispose);
        await tester.pumpWidget(_host(harness));
        await tester.pumpAndSettle();
        _expectNoTrialControls();
        final recipe = switch (mode) {
          CraftMode.alchemy => 'Intermediate Reagent',
          CraftMode.cooking => 'Beer',
          CraftMode.processing => 'Wheat Flour',
        };
        final ingredient = mode == CraftMode.alchemy ? 'Sunrise Herb' : 'Wheat';
        final perCraft = switch (mode) {
          CraftMode.alchemy => 'x2',
          CraftMode.cooking => 'x5',
          CraftMode.processing => 'x1',
        };
        for (final want in ['10', '13709']) {
          final input = find.descendant(
            of: find.byKey(PlannerActionKeys.p02),
            matching: find.byType(EditableText),
          );
          await tester.enterText(input, want);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          final step = harness.controller.active.plan.value.steps.firstWhere(
            (step) => step.name == recipe,
          );
          _expectSummary(
            tester,
            step,
            processing: mode == CraftMode.processing,
          );
          expect(
            tester
                .widget<Text>(_quantity(recipe, ingredient, perCraft: true))
                .data,
            perCraft,
          );
          expect(
            tester.widget<Text>(_quantity(recipe, ingredient)).data,
            formatQuantity(step.ingredients.single.need),
          );
          _expectNeedQuantities(
            tester,
            harness.controller.active.plan.value.missing.single,
          );
        }
        harness.controller.active.updateState(
          (state) => state.copyWith(
            ignoreIngredientInventory: false,
            inventory: {ingredient: 100000},
          ),
          immediate: true,
        );
        await tester.pumpAndSettle();
        final step = harness.controller.active.plan.value.steps.firstWhere(
          (step) => step.name == recipe,
        );
        expect(step.ingredients.single.missing, 0);
        expect(
          tester.widget<Text>(_quantity(recipe, ingredient)).data,
          formatQuantity(step.ingredients.single.need),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'default Need First reflects Add and retains drafts across responsive layouts',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(includeLightstoneNeed: true);
      addTearDown(harness.controller.dispose);
      const ingredient = 'Imperfect Lightstone of Flora';
      await tester.pumpWidget(_host(harness, size: const Size(916, 674)));
      await tester.pumpAndSettle();
      _expectNoTrialControls();
      _expectNeedQuantities(
        tester,
        harness.controller.active.plan.value.missing.single,
      );
      final ownedField = find.descendant(
        of: find.byKey(PlannerActionKeys.row('P18', ingredient)),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(ownedField);
      await tester.enterText(ownedField, '12');
      final quantities = find.byWidgetPredicate(
        (widget) =>
            widget is PlannerNeedQuantities && widget.stableId == ingredient,
      );
      expect(
        tester.getRect(quantities).contains(tester.getCenter(ownedField)),
        isTrue,
      );
      await tester.pumpWidget(_host(harness));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(ownedField).controller!.text, '12');
      expect(
        harness.controller.active.state.value.inventory[ingredient],
        isNull,
      );
      await tester.pumpWidget(_host(harness, size: const Size(916, 674)));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(ownedField).controller!.text, '12');
      expect(
        tester.getRect(ownedField).top,
        greaterThan(
          tester.getRect(_needQuantity(ingredient, 'Missing')).bottom,
        ),
      );
      await _tap(tester, find.byKey(PlannerActionKeys.row('P19', ingredient)));
      expect(harness.controller.active.state.value.inventory[ingredient], 12);
      expect(
        harness.controller.active.state.value.ignoreIngredientInventory,
        isFalse,
      );
      final afterAdd = harness.controller.active.plan.value.missing.single;
      expect(afterAdd.need, 40);
      expect(afterAdd.have, 12);
      expect(afterAdd.missing, 28);
      _expectNeedQuantities(tester, afterAdd);
      expect(tester.widget<TextField>(ownedField).controller!.text, '0');
      await tester.pumpWidget(_host(harness));
      await tester.pumpAndSettle();
      _expectNeedQuantities(tester, afterAdd);
      expect(harness.controller.active.state.value.inventory[ingredient], 12);
      await tester.ensureVisible(ownedField);
      await tester.enterText(ownedField, '28');
      await _tap(tester, find.byKey(PlannerActionKeys.row('P19', ingredient)));
      expect(harness.controller.active.state.value.inventory[ingredient], 40);
      expect(harness.controller.active.plan.value.missing, isEmpty);
      expect(find.byType(PlannerNeedQuantities), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default quantities preserve the original mass-processing summary',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(activeMode: CraftMode.processing);
      addTearDown(harness.controller.dispose);
      harness.controller.active.updateState(
        (state) => state.copyWith(
          want: 13709,
          useMassProcessing: true,
          processingMastery: 600,
        ),
        immediate: true,
      );
      await tester.pumpWidget(_host(harness));
      await tester.pumpAndSettle();
      final step = harness.controller.active.plan.value.steps.single;
      expect(step.count, 13709);
      expect(step.batchSize, 40);
      expect(step.batchCount, 343);
      _expectSummary(tester, step, processing: true);
      expect(
        find.descendant(
          of: _summary(step.name),
          matching: find.text('Mass batches 343 ×40'),
        ),
        findsOneWidget,
      );
      _expectNoBroadRedesign();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default quantities preserve substitute, quality, copy, map, and completion actions',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(
        resolveMapLookup: (name) async => PlannerMapLookupAvailability(
          materialName: name,
          hasManualGathering: true,
          manualResourceId: 'sunrise-herb',
          manualLocationCount: 1,
          hasWorkerNodes: false,
        ),
      );
      addTearDown(harness.controller.dispose);
      await tester.pumpWidget(
        _host(harness, spec: SakuraNightGardenSpec.theme),
      );
      await tester.pumpAndSettle();
      final mapRegion = find.byKey(
        PlannerActionKeys.mapLookupRegion(
          'queue:Intermediate Reagent:Sunrise Herb',
        ),
      );
      await tester.ensureVisible(mapRegion);
      await tester.tap(
        mapRegion,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await _tap(
        tester,
        find.byKey(
          PlannerActionKeys.mapLookupAction(
            'queue:Intermediate Reagent:Sunrise Herb',
            PlannerMapLookupSource.manualGathering.name,
          ),
        ),
      );
      expect(harness.mapLookupRequests.single.materialName, 'Sunrise Herb');
      await _tap(
        tester,
        find.byKey(PlannerActionKeys.row('P10', 'Intermediate Reagent')),
      );
      expect(harness.copied, ['Intermediate Reagent']);
      final expansion = find.byKey(
        PlannerActionKeys.row('P09', 'Intermediate Reagent'),
      );
      await _tap(tester, expansion);
      expect(_quantity('Intermediate Reagent', 'Sunrise Herb'), findsNothing);
      await _tap(tester, expansion);
      await _tap(
        tester,
        find.byKey(
          PlannerActionKeys.row('P12', 'step:Intermediate Reagent:Wild Herbs'),
        ),
      );
      await _tap(
        tester,
        find.byKey(PlannerActionKeys.row('P13', 'Silver Azalea')),
      );
      expect(
        harness.controller.active.state.value.substituteChoices.values,
        contains('Silver Azalea'),
      );
      expect(
        tester
            .widget<Text>(
              _quantity('Intermediate Reagent', 'Sunrise Herb', perCraft: true),
            )
            .data,
        'x4',
      );
      expect(
        tester
            .widget<Text>(_quantity('Intermediate Reagent', 'Sunrise Herb'))
            .data,
        '40',
      );
      final quality = find.descendant(
        of: find.byKey(
          PlannerActionKeys.row('P14', 'Intermediate Reagent:Sunrise Herb'),
        ),
        matching: find.byType(InkWell),
      );
      await _tap(tester, quality.last);
      expect(
        harness.controller.active.state.value.ingredientGrades.values,
        contains('special'),
      );
      expect(
        tester
            .widget<Text>(
              _quantity('Intermediate Reagent', 'Sunrise Herb', perCraft: true),
            )
            .data,
        'x1',
      );
      expect(
        tester
            .widget<Text>(_quantity('Intermediate Reagent', 'Sunrise Herb'))
            .data,
        '10',
      );
      // The manual quality choice already fetched and revealed prices.
      expect(find.byKey(PlannerActionKeys.p16), findsOneWidget);
      await _tap(tester, find.byKey(PlannerActionKeys.p16));
      await _tap(tester, find.byKey(PlannerActionKeys.p15));
      expect(harness.marketRequest, isNotNull);
      expect(
        harness.controller.active.state.value.market.prices['Sunrise Herb'],
        1200,
      );
      await _tap(
        tester,
        find.byKey(PlannerActionKeys.row('P08', 'Clear Liquid Reagent')),
      );
      expect(
        harness.controller.active.state.value.completedSteps,
        contains('Clear Liquid Reagent'),
      );
      expect(harness.controller.active.plan.value.steps, isEmpty);
      await _tap(tester, find.byKey(PlannerActionKeys.p07));
      expect(harness.controller.active.state.value.completedSteps, isEmpty);
      expect(_summary('Intermediate Reagent'), findsOneWidget);
      expect(_summary('Clear Liquid Reagent'), findsOneWidget);
      _expectNeedQuantities(
        tester,
        harness.controller.active.plan.value.missing.single,
        spec: SakuraNightGardenSpec.theme,
      );
      _expectNoTrialControls();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('default quantities follow recipe route and batch choices', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(includeRecipeVariants: true);
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(_host(harness, spec: IlluminatedLedgerSpec.theme));
    await tester.pumpAndSettle();
    await _tap(
      tester,
      find.byKey(
        RecipeVariantSelector.choiceKey('Clear Liquid Reagent', 'herb-route'),
      ),
    );
    await _tap(
      tester,
      find.byKey(
        RecipeVariantSelector.batchChoiceKey('Clear Liquid Reagent', 10),
      ),
    );
    expect(
      harness.controller.active.selectedRecipeVariantId('Clear Liquid Reagent'),
      'herb-route-10x',
    );
    final expansion = find.byKey(
      PlannerActionKeys.row('P09', 'Clear Liquid Reagent'),
    );
    if (_quantity('Clear Liquid Reagent', 'Silver Azalea').evaluate().isEmpty) {
      await _tap(tester, expansion);
    }
    expect(
      tester
          .widget<Text>(
            _quantity('Clear Liquid Reagent', 'Silver Azalea', perCraft: true),
          )
          .data,
      'x40',
    );
    expect(
      tester
          .widget<Text>(_quantity('Clear Liquid Reagent', 'Silver Azalea'))
          .data,
      '40',
    );
    _expectSummary(tester, harness.controller.active.plan.value.steps.single);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real Adaptation chain keeps choices off reagents and preserves actual elixir and blood substitutes',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final original = (await tester.runAsync(ApplicationTestHarness.create))!;
      final real = original.rebindControllerInCurrentZone();
      await tester.runAsync(original.disposeControllerOnly);
      final fixture = PlannerTestHarness();
      addTearDown(fixture.controller.dispose);
      final controller = real.bundle.controller.active;
      controller.selectTarget('Adaptation Draught');
      controller.commitAmount('100');
      controller.selectRecipeVariant(
        recipeName: 'Adaptation Draught',
        variantId: 'simple-alchemy-10x',
      );
      final variant = controller
          .recipeDefinition('Adaptation Draught')!
          .variantById('simple-alchemy-10x')!;
      for (final ingredient in variant.ingredients) {
        if (ingredient.options.length > 1) {
          controller.selectSubstitute(
            parentName: 'Adaptation Draught',
            ingredient: ingredient,
            selection: ingredient.name,
          );
        }
      }
      try {
        final plan = controller.plan.value;
        expect(
          plan.steps.map((step) => step.name),
          containsAll([
            'Clear Liquid Reagent',
            "Clown's Blood",
            'Helix Elixir',
          ]),
        );
        await tester.pumpWidget(
          _host(
            fixture,
            application: real.bundle.controller,
            spec: SakuraNightGardenSpec.theme,
          ),
        );
        await tester.pumpAndSettle();
        for (final name in ['Clear Liquid Reagent', "Clown's Blood"]) {
          final card = find.byKey(ValueKey('queue:$name'));
          await tester.ensureVisible(card);
          await tester.pumpAndSettle();
          expect(card, findsOneWidget);
          expect(
            find.byKey(PlannerActionKeys.row('P12', 'queue-title:$name')),
            findsNothing,
          );
        }
        final blood = plan.steps.singleWhere(
          (step) => step.name == "Clown's Blood",
        );
        final bloodIngredient = blood.ingredients.firstWhere(
          (ingredient) =>
              ingredient.options.length > 1 &&
              ingredient.name.contains('Blood'),
        );
        expect(
          bloodIngredient.options.every((name) => name.contains('Blood')),
          isTrue,
        );
        final bloodChoice = find.byKey(
          PlannerActionKeys.row(
            'P12',
            "step:Clown's Blood:${bloodIngredient.substituteGroup}",
          ),
        );
        if (bloodChoice.evaluate().isEmpty) {
          await _tap(
            tester,
            find.byKey(PlannerActionKeys.row('P09', "Clown's Blood")),
          );
        }
        await _tap(tester, bloodChoice);
        final alternative = bloodIngredient.options.firstWhere(
          (name) => name != bloodIngredient.name,
        );
        await _tap(
          tester,
          find.byKey(PlannerActionKeys.row('P13', alternative)),
        );
        expect(
          controller.plan.value.steps
              .singleWhere((step) => step.name == "Clown's Blood")
              .ingredients
              .any((ingredient) => ingredient.name == alternative),
          isTrue,
        );

        final elixirChoice = find.byKey(
          PlannerActionKeys.row('P12', 'queue-title:Helix Elixir'),
        );
        await tester.scrollUntilVisible(
          elixirChoice,
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await _tap(tester, elixirChoice);
        await _tap(
          tester,
          find.byKey(PlannerActionKeys.row('P13', 'Splendid Helix Elixir')),
        );
        final draught = controller.plan.value.steps.singleWhere(
          (step) => step.name == 'Adaptation Draught',
        );
        expect(
          draught.ingredients.any(
            (ingredient) => ingredient.name == 'Splendid Helix Elixir',
          ),
          isTrue,
        );
        expect(
          find.byKey(
            PlannerActionKeys.row('P12', 'queue-title:Clear Liquid Reagent'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(PlannerActionKeys.row('P12', "queue-title:Clown's Blood")),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await real.disposeControllerOnly();
        await tester.runAsync(
          () => real.temporaryDirectory.delete(recursive: true),
        );
      }
    },
  );

  for (final spec in _themes) {
    testWidgets('A2 groups market details beside the item in ${spec.id}', (
      tester,
    ) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final fixture = PlannerTestHarness();
      addTearDown(fixture.controller.dispose);
      fixture.controller.active.setPricesVisible(true);
      await tester.pumpWidget(
        _host(fixture, spec: spec, size: const Size(1500, 940)),
      );
      await tester.pumpAndSettle();
      final row = find.byType(PlannerNeedQuantities).first;
      final name = find
          .descendant(of: row, matching: find.text('Sunrise Herb'))
          .first;
      final stock = find.descendant(
        of: row,
        matching: find.text('Vendor item'),
      );
      final price = find.descendant(of: row, matching: find.text('500 each'));
      final total = find.descendant(
        of: row,
        matching: find.textContaining('Total '),
      );
      final missing = _needQuantity('Sunrise Herb', 'Missing');
      expect(
        tester.getRect(price).top,
        greaterThan(tester.getRect(missing).bottom),
      );
      expect(tester.getRect(stock).left, closeTo(tester.getRect(name).left, 4));
      expect(
        tester.getRect(price).left - tester.getRect(stock).right,
        closeTo(14, .01),
      );
      final priceBounds = tester.getRect(price);
      final totalBounds = tester.getRect(total);
      if ((totalBounds.top - priceBounds.top).abs() < 1) {
        expect(totalBounds.left - priceBounds.right, closeTo(14, .01));
      } else {
        expect(totalBounds.top, greaterThan(priceBounds.bottom));
        expect(totalBounds.left, closeTo(tester.getRect(stock).left, .01));
      }
      expect(
        find.descendant(of: row, matching: find.byType(Divider)),
        findsNothing,
      );
      final pricedHeight = tester.getSize(row).height;
      fixture.controller.active.setPricesVisible(false);
      await tester.pumpAndSettle();
      expect(stock, findsNothing);
      expect(price, findsNothing);
      expect(tester.getSize(row).height, lessThan(pricedHeight));
      expect(tester.takeException(), isNull);
    });
  }

  const capture = bool.fromEnvironment('CAPTURE_PLANNER_QUANTITIES');
  const captureA2 = bool.fromEnvironment('CAPTURE_NEED_A2');
  const captureTextPercent = int.fromEnvironment(
    'PLANNER_QUANTITY_CAPTURE_TEXT_PERCENT',
    defaultValue: 100,
  );
  if (capture || captureA2) {
    setUpAll(_loadCaptureFonts);
    for (final spec in _themes) {
      for (final size in const [Size(1200, 752), Size(1500, 940)]) {
        testWidgets(
          'capture default quantities ${spec.id} $size full real-catalog workspace',
          (tester) async {
            configureApplicationTestSurface(
              tester,
              size,
              textScaleFactor: captureTextPercent / 100,
            );
            final original = (await tester.runAsync(
              () => ApplicationTestHarness.create(
                backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
              ),
            ))!;
            final harness = original.rebindControllerInCurrentZone();
            await tester.runAsync(original.disposeControllerOnly);
            final controller = harness.bundle.controller;
            controller.active.selectTarget(
              captureA2 ? 'Adaptation Draught' : 'Clear Liquid Reagent',
            );
            controller.active.commitAmount(captureA2 ? '100' : '34272');
            if (captureA2) {
              controller.active.replaceMarketValues(
                prices: {
                  for (final row in controller.active.plan.value.missing)
                    row.name: 5000,
                },
                stock: {
                  for (final row in controller.active.plan.value.missing)
                    row.name: row.name == 'Thuja Sap' ? 0 : 125000,
                },
                unlistedItemNames: const [],
                fetchedAt: DateTime.utc(
                  2026,
                  9,
                  26,
                  21,
                  30,
                ).millisecondsSinceEpoch,
              );
              controller.active.setPricesVisible(true);
            }
            const root = ValueKey('planner-quantity-capture-root');
            try {
              await tester.pumpWidget(
                RepaintBoundary(
                  key: root,
                  child: BdoCraftPlannerApp(
                    enableOpportunityAutoCheck: false,
                    applicationFuture: Future.value(harness.bundle),
                    marketGateway: const EmptyMarketGateway(),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              for (final element in find.byType(Image).evaluate()) {
                await tester.runAsync(
                  () => precacheImage((element.widget as Image).image, element),
                );
              }
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(find.byType(PlannerNeedQuantities), findsWidgets);
              expect(find.byType(PlannerQuantityBadge), findsWidgets);
              _expectNoTrialControls();
              _expectNoBroadRedesign();
              _expectVisibleNeedRowsEmphasizeMissing(tester);
              for (final element in find.byWidgetPredicate((widget) {
                final key = widget.key;
                return widget is Text &&
                    key is ValueKey<String> &&
                    key.value.startsWith('planner-ingredient-batch-quantity:');
              }).evaluate()) {
                final key = element.widget.key! as ValueKey<String>;
                final stableId = key.value.substring(
                  'planner-ingredient-batch-quantity:'.length,
                );
                _expectMatchingQuantityBadges(
                  tester,
                  find.byKey(
                    ValueKey('planner-ingredient-per-craft-quantity:$stableId'),
                  ),
                  find.byKey(key),
                  spec: spec,
                  scale: captureTextPercent / 100,
                  expectInline: captureTextPercent == 100,
                );
              }
              for (final prices in captureA2 ? [true, false] : [false]) {
                if (captureA2) {
                  controller.active.setPricesVisible(prices);
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull);
                }
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(root),
                );
                await tester.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  try {
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    const directory = String.fromEnvironment(
                      'PLANNER_QUANTITY_CAPTURE_DIRECTORY',
                      defaultValue: 'tmp/planner-quantity-default',
                    );
                    final file = File(
                      '$directory/${spec.id}-${size.width.toInt()}x${size.height.toInt()}${captureTextPercent == 100 ? '' : '-text$captureTextPercent'}${captureA2 ? (prices ? '-prices' : '-hidden') : ''}.png',
                    );
                    await file.parent.create(recursive: true);
                    await file.writeAsBytes(
                      bytes!.buffer.asUint8List(),
                      flush: true,
                    );
                  } finally {
                    image.dispose();
                  }
                });
              }
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await harness.disposeControllerOnly();
              await tester.runAsync(
                () => harness.temporaryDirectory.delete(recursive: true),
              );
            }
          },
        );
      }
    }
  }
}

Widget _host(
  PlannerTestHarness harness, {
  PlannerApplicationController? application,
  ThemeSpec spec = StandardSpec.theme,
  Size size = const Size(1216, 862),
  double scale = 1,
}) => AppOverlayCoordinatorHost(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: spec.materialTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: ThemeSpecScope(
      spec: spec,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: PlannerView(
              controller: (application ?? harness.controller).active,
              externalActions: harness.actions,
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _expectSummary(
  WidgetTester tester,
  PlanStep step, {
  bool processing = false,
}) {
  expect(_summary(step.name), findsOneWidget);
  final header = find.byKey(ValueKey('planner-queue-heading:${step.name}'));
  expect(
    find.descendant(of: header, matching: _summary(step.name)),
    findsOneWidget,
  );
  final bounds = tester.getRect(header);
  for (final entry in {
    'Craft': step.count,
    'Results': step.produced,
    'Need': step.demand,
  }.entries) {
    final finder = find.byKey(
      ValueKey('planner-craft-quantity:${step.name}:${entry.key}'),
    );
    expect(tester.widget<Text>(finder).data, formatQuantity(entry.value));
    expect(tester.widget<Text>(finder).style?.fontSize, 16);
    expect(tester.widget<Text>(finder).style?.fontWeight, FontWeight.w700);
    final valueBounds = tester.getRect(finder);
    expect(valueBounds.left, greaterThanOrEqualTo(bounds.left));
    expect(valueBounds.right, lessThanOrEqualTo(bounds.right + .01));
    expect(valueBounds.top, greaterThanOrEqualTo(bounds.top));
    expect(valueBounds.bottom, lessThanOrEqualTo(bounds.bottom + .01));
  }
  if (step.batchSize > 1) {
    expect(
      find.descendant(
        of: _summary(step.name),
        matching: find.text(
          'Mass batches ${formatQuantity(step.batchCount)} ×${step.batchSize}',
        ),
      ),
      findsOneWidget,
    );
  }
}

void _expectNoBroadRedesign() {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget.runtimeType.toString() == 'PlannerPreviewStepSummary' ||
          widget.runtimeType.toString() == 'PlannerPreviewIngredientBand',
    ),
    findsNothing,
  );
  expect(find.text('Per craft'), findsNothing);
}

void _expectNoTrialControls() {
  expect(find.byKey(_removedToggleKey), findsNothing);
  expect(find.text('Try quantity B'), findsNothing);
  expect(find.text('Quantity B · Use original'), findsNothing);
  expect(
    find.bySemanticsLabel(
      RegExp('Try Planner quantity layout B|Use original Planner layout'),
    ),
    findsNothing,
  );
}

void _expectOriginalTotalColumn(WidgetTester tester, Finder total) {
  final fitted = find.ancestor(of: total, matching: find.byType(FittedBox));
  expect(fitted, findsOneWidget);
  expect(tester.widget<FittedBox>(fitted).fit, BoxFit.scaleDown);
  expect(tester.widget<FittedBox>(fitted).alignment, Alignment.centerRight);
  expect(
    find.ancestor(
      of: total,
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 86,
      ),
    ),
    findsOneWidget,
  );
}

void _expectMatchingQuantityBadges(
  WidgetTester tester,
  Finder formula,
  Finder total, {
  ThemeSpec spec = StandardSpec.theme,
  double scale = 1,
  bool expectInline = false,
}) {
  final formulaStyle = tester.widget<Text>(formula).style!;
  expect(tester.widget<Text>(total).style, formulaStyle);
  expect(formulaStyle.fontSize, 16);
  expect(formulaStyle.fontWeight, FontWeight.w600);
  expect(formulaStyle.fontStyle, FontStyle.normal);
  expect(formulaStyle.fontFeatures, const [FontFeature.tabularFigures()]);
  expect(formulaStyle.color, spec.palette.text);
  if (expectInline) {
    final identityBounds = tester.getRect(
      find.ancestor(
        of: formula,
        matching: find.byType(PlannerIngredientIdentity),
      ),
    );
    final totalBounds = tester.getRect(total);
    expect(totalBounds.top, lessThan(identityBounds.bottom));
    expect(totalBounds.bottom, greaterThan(identityBounds.top));
  }
  BoxDecoration? firstDecoration;
  EdgeInsetsGeometry? firstPadding;
  for (final quantity in [formula, total]) {
    final badge = find.ancestor(
      of: quantity,
      matching: find.byType(PlannerQuantityBadge),
    );
    expect(badge, findsOneWidget);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: badge,
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    final padding = tester
        .widget<Padding>(
          find.descendant(of: badge, matching: find.byType(Padding)),
        )
        .padding;
    firstDecoration ??= decoration;
    firstPadding ??= padding;
    expect(decoration, firstDecoration);
    expect(padding, firstPadding);
    expect(decoration.color, spec.palette.text.withValues(alpha: 0.09));
    expect(decoration.borderRadius, BorderRadius.circular(3));
    expect(padding, const EdgeInsets.symmetric(horizontal: 6, vertical: 2));
    expect(
      find.ancestor(of: quantity, matching: find.byType(FittedBox)),
      findsNothing,
    );
    final paragraph = tester.renderObject<RenderParagraph>(quantity);
    expect(paragraph.textScaler.scale(16), closeTo(16 * scale, 0.01));
    final origin = paragraph.localToGlobal(Offset.zero);
    final horizontal = paragraph.localToGlobal(const Offset(10, 0));
    final vertical = paragraph.localToGlobal(const Offset(0, 10));
    expect((horizontal - origin).distance, closeTo(10, 0.01));
    expect((vertical - origin).distance, closeTo(10, 0.01));
    final textBounds = tester.getRect(quantity);
    final badgeBounds = tester.getRect(badge);
    expect(badgeBounds.width, closeTo(textBounds.width + 12, 0.01));
    expect(badgeBounds.height, closeTo(textBounds.height + 4, 0.01));
  }
}

void _expectVisibleNeedRowsEmphasizeMissing(WidgetTester tester) {
  final viewport = Offset.zero & tester.view.physicalSize;
  var visibleRows = 0;
  for (final widget in tester.widgetList<PlannerNeedQuantities>(
    find.byType(PlannerNeedQuantities),
  )) {
    final root = find.byKey(widget.key!);
    if (!tester.getRect(root).overlaps(viewport)) continue;
    visibleRows += 1;
    final need = tester.getRect(_needQuantity(widget.stableId, 'Need'));
    final have = tester.getRect(_needQuantity(widget.stableId, 'Have'));
    final missing = tester.getRect(_needQuantity(widget.stableId, 'Missing'));
    expect(have.top, greaterThanOrEqualTo(need.top - 1));
    expect(missing.top, greaterThanOrEqualTo(need.top - 2));
    expect(need.overlaps(have), isFalse);
    expect(have.overlaps(missing), isFalse);
  }
  expect(visibleRows, greaterThan(0));
}

void _expectNeedQuantities(
  WidgetTester tester,
  MissingMaterial row, {
  ThemeSpec spec = StandardSpec.theme,
}) {
  final root = find.byKey(ValueKey('planner-need-quantities:${row.key}'));
  expect(root, findsOneWidget);
  final rootBounds = tester.getRect(root);
  final bounds = <Rect>[];
  for (final entry in {
    'Need': row.need,
    'Have': row.have,
    'Missing': row.missing,
  }.entries) {
    final finder = _needQuantity(row.key, entry.key);
    final text = tester.widget<Text>(finder);
    expect(text.data, formatQuantity(entry.value));
    expect(text.style?.fontSize, entry.key == 'Missing' ? 16 : 14);
    expect(
      text.style?.fontWeight,
      entry.key == 'Missing' ? FontWeight.w700 : FontWeight.w500,
    );
    expect(text.style?.color, spec.palette.text);
    final label = tester.widget<Text>(
      find.descendant(of: root, matching: find.text(entry.key)),
    );
    expect(label.style?.fontSize, 12.5);
    final valueBounds = tester.getRect(finder);
    expect(valueBounds.left, greaterThanOrEqualTo(rootBounds.left));
    expect(valueBounds.right, lessThanOrEqualTo(rootBounds.right + 0.01));
    expect(valueBounds.top, greaterThanOrEqualTo(rootBounds.top));
    expect(valueBounds.bottom, lessThanOrEqualTo(rootBounds.bottom + 0.01));
    for (final previous in bounds) {
      expect(previous.overlaps(valueBounds), isFalse);
    }
    bounds.add(valueBounds);
  }
}

Future<void> _loadCaptureFonts() async {
  final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (flutterRoot.parent.path == flutterRoot.path) {
      throw StateError('Flutter font directory not found.');
    }
    flutterRoot = flutterRoot.parent;
  }
  final materialFonts =
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts';
  for (final entry in {
    'Segoe UI': [
      '$windowsRoot/Fonts/segoeui.ttf',
      '$windowsRoot/Fonts/seguisb.ttf',
      '$windowsRoot/Fonts/segoeuib.ttf',
    ],
    'Georgia': [
      '$windowsRoot/Fonts/georgia.ttf',
      '$windowsRoot/Fonts/georgiab.ttf',
      '$windowsRoot/Fonts/georgiai.ttf',
    ],
    'Roboto': [
      '$materialFonts/roboto-regular.ttf',
      '$materialFonts/roboto-bold.ttf',
    ],
    'MaterialIcons': ['$materialFonts/materialicons-regular.otf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
