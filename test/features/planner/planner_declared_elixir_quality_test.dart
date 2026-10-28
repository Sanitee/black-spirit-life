import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import 'planner_test_fixture.dart';

const _target = 'Harmony Draught - Edania';
const _pairs = {
  'Elixir of Edania': 'Strong Elixir of Edania',
  'Elixir of Will': 'Elixir of Remarkable Will',
};

void main() {
  testWidgets(
    'declared elixir quality preserves both real Harmony batch formulas',
    (tester) async {
      final harness = await _createHarness(tester);
      final mode = harness.bundle.controller.active;
      for (final variant in ['simple-alchemy-10x', 'simple-alchemy-100x']) {
        mode.selectRecipeVariant(recipeName: _target, variantId: variant);
        for (final pair in _pairs.entries) {
          expect(
            mode.declaredBlueIngredientPair(
              parentName: _target,
              ingredientName: pair.key,
            ),
            (normal: pair.key, blue: pair.value),
          );
          expect(
            mode.availableIngredientGrades(
              parentName: _target,
              selectedName: pair.key,
            ),
            ['normal', 'blue'],
          );
          for (final grade in ['normal', 'blue', 'normal']) {
            mode.selectIngredientGrade(
              parentName: _target,
              ingredientName: pair.key,
              selectedName: pair.key,
              grade: grade,
            );
            final input = _input(mode, pair.key);
            expect(input.name, grade == 'blue' ? pair.value : pair.key);
            expect(input.need, grade == 'blue' ? 500 : 1500);
            expect(
              input.grade,
              'normal',
              reason: 'The declared 3:1 option must not convert twice.',
            );
            expect(
              mode.selectedIngredientGrade(
                parentName: _target,
                ingredientName: pair.key,
                selectedName: input.baseName,
              ),
              grade,
            );
          }
        }
      }
      await _dispose(tester, harness);
    },
  );

  testWidgets(
    'declared elixir choices survive stock updates and Auto clears only its slot',
    (tester) async {
      final harness = await _createHarness(tester);
      final mode = harness.bundle.controller.active;
      for (final pair in _pairs.entries) {
        mode.selectIngredientGrade(
          parentName: _target,
          ingredientName: pair.key,
          selectedName: pair.key,
          grade: 'blue',
        );
      }
      mode.updateState(
        (state) => state.copyWith(
          market: state.market.copyWith(
            stock: {
              ...state.market.stock,
              for (final rare in _pairs.values) rare: 0,
            },
          ),
        ),
      );
      expect(_input(mode, 'Elixir of Edania').name, 'Strong Elixir of Edania');
      expect(_input(mode, 'Elixir of Will').name, 'Elixir of Remarkable Will');
      final before = mode.state.value.substituteChoices;
      final rebound = harness.rebindControllerInCurrentZone();
      final restored = rebound.bundle.controller.active;
      expect(restored.state.value.substituteChoices, before);
      expect(
        restored.selectedIngredientGrade(
          parentName: _target,
          ingredientName: 'Elixir of Edania',
          selectedName: 'Strong Elixir of Edania',
        ),
        'blue',
      );
      restored.selectIngredientGrade(
        parentName: _target,
        ingredientName: 'Elixir of Edania',
        selectedName: 'Strong Elixir of Edania',
        grade: 'auto',
      );
      expect(_input(restored, 'Elixir of Edania').name, 'Elixir of Edania');
      expect(_input(restored, 'Elixir of Edania').need, 1500);
      expect(
        _input(restored, 'Elixir of Will').name,
        'Elixir of Remarkable Will',
      );
      expect(
        restored.hasManualIngredientChoice(
          parentName: _target,
          ingredientName: 'Elixir of Edania',
          selectedName: 'Elixir of Edania',
        ),
        isFalse,
      );
      expect(
        restored.hasManualIngredientChoice(
          parentName: _target,
          ingredientName: 'Elixir of Will',
          selectedName: 'Elixir of Remarkable Will',
        ),
        isTrue,
      );
      await rebound.disposeControllerOnly();
      await _dispose(tester, harness);
    },
  );

  testWidgets(
    'real Edania queue and Need First use the existing green and blue squares',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final mode = harness.bundle.controller.active;
      await tester.pumpWidget(_host(mode));
      await tester.pumpAndSettle();
      for (final pair in _pairs.entries) {
        final queueQuality = find.byKey(
          PlannerActionKeys.row('P14', 'queue-title:$_target:${pair.key}'),
        );
        await _showInList(tester, queueQuality, queue: true);
        expect(
          find.byKey(PlannerActionKeys.row('P12', 'queue-title:${pair.key}')),
          findsNothing,
        );
        expect(_quality(queueQuality, 'Normal'), findsOneWidget);
        expect(_quality(queueQuality, 'Blue Grade'), findsOneWidget);
        await tester.tap(_quality(queueQuality, 'Blue Grade'));
        await tester.pumpAndSettle();
        expect(_input(mode, pair.key).need, 500);
        expect(_input(mode, pair.key).name, pair.value);

        final needQuality = find.byKey(ValueKey('need-quality:${pair.value}'));
        await _showInList(tester, needQuality);
        expect(
          tester
              .widget<Semantics>(_quality(needQuality, 'Blue Grade'))
              .properties
              .selected,
          isTrue,
        );
        await tester.tap(_quality(needQuality, 'Normal'));
        await tester.pumpAndSettle();
        expect(_input(mode, pair.key).name, pair.key);
        expect(_input(mode, pair.key).need, 1500);
        await _resetLists(tester);
      }
      // The final recipe's expanded ingredients use the same controls too.
      mode.toggleIngredients(_target);
      final ingredientQuality = find.byKey(
        PlannerActionKeys.row('P14', '$_target:Elixir of Edania'),
      );
      await _showInList(tester, ingredientQuality, queue: true);
      expect(_quality(ingredientQuality, 'Blue Grade'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester, harness);
    },
  );

  testWidgets(
    'ordinary alternatives retain their expanded substitute chooser',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(includeQueueTitleSubstitutes: true);
      addTearDown(harness.controller.dispose);
      expect(
        harness.controller.active.declaredBlueIngredientPair(
          parentName: 'Clear Liquid Reagent',
          ingredientName: 'Intermediate Reagent',
        ),
        isNull,
      );
      await tester.pumpWidget(harness.plannerHost());
      await tester.pumpAndSettle();
      final anchor = find.byKey(
        PlannerActionKeys.row('P12', 'queue-title:Intermediate Reagent'),
      );
      expect(anchor, findsOneWidget);
      await tester.tap(anchor);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Substitute choices for Intermediate Reagent'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(PlannerActionKeys.row('P13', 'Alternate Reagent')),
      );
      await tester.pumpAndSettle();
      expect(
        harness
            .controller
            .active
            .state
            .value
            .substituteChoices['recipe:Clear Liquid Reagent:Reagent Base'],
        'Alternate Reagent',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

PlanStepIngredient _input(ModeFeatureController mode, String original) => mode
    .plan
    .value
    .steps
    .singleWhere((step) => step.name == _target)
    .ingredients
    .singleWhere((ingredient) => ingredient.original == original);

Future<ApplicationTestHarness> _createHarness(WidgetTester tester) async {
  final original = (await tester.runAsync(ApplicationTestHarness.create))!;
  final harness = original.rebindControllerInCurrentZone();
  await tester.runAsync(original.disposeControllerOnly);
  final mode = harness.bundle.controller.active;
  mode.selectTarget(_target);
  mode.commitAmount('500');
  mode.selectRecipeVariant(
    recipeName: _target,
    variantId: 'simple-alchemy-10x',
  );
  mode.updateState(
    (state) => state.copyWith(
      inventory: const {'Harmony Draught': 500},
      ignoreTargetInventory: true,
      ignoreIngredientInventory: false,
      market: state.market.copyWith(
        prices: {
          for (final normal in _pairs.keys) normal: 100,
          for (final rare in _pairs.values) rare: 10000,
        },
        stock: {
          for (final item in [..._pairs.keys, ..._pairs.values]) item: 10000,
        },
        unlistedItemNames: const [],
      ),
    ),
  );
  return harness;
}

Widget _host(ModeFeatureController mode) {
  final spec = SakuraNightGardenSpec.theme;
  return AppOverlayCoordinatorHost(
    child: MaterialApp(
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: PlannerView(
              controller: mode,
              externalActions: PlannerExternalActions(
                openRecipeBook: (_) {},
                copyName: (_) async {},
                checkPrices: (_) async => const PlannerMarketRefresh(
                  prices: {},
                  stock: {},
                  unlistedItemNames: {},
                  fetchedAt: 0,
                  summary: '',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _quality(Finder parent, String label) => find.descendant(
  of: parent,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.properties.label == '$label quality',
  ),
);

Future<void> _showInList(
  WidgetTester tester,
  Finder target, {
  bool queue = false,
}) async {
  final list = find.byKey(
    PageStorageKey<String>(
      queue ? 'planner-craft-queue' : 'planner-need-first',
    ),
  );
  await tester.scrollUntilVisible(
    target,
    160,
    scrollable: find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _resetLists(WidgetTester tester) async {
  for (final key in ['planner-craft-queue', 'planner-need-first']) {
    final controller = tester
        .widget<ListView>(find.byKey(PageStorageKey<String>(key)))
        .controller;
    if (controller != null && controller.hasClients) controller.jumpTo(0);
  }
  await tester.pumpAndSettle();
}

Future<void> _dispose(
  WidgetTester tester,
  ApplicationTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await harness.disposeControllerOnly();
  await tester.runAsync(
    () => harness.temporaryDirectory.delete(recursive: true),
  );
}
