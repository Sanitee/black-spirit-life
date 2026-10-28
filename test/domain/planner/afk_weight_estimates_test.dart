import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/afk_weight_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = AfkWeightCalculator();
  final rules = PlannerRules(
    itemWeightIds: const {'Raw': '1', 'Result': '2'},
    itemWeightsLtById: const {'1': .1, '2': .1},
  );
  AfkWeightCalculation calculate({
    String type = 'processing',
    CraftMode mode = CraftMode.processing,
    double? minimum = 1,
    double? maximum = 4,
    double base = 1,
    double? expected = 2.5,
    double input = 1,
    int batch = 1,
    double buffer = 10,
  }) => calculator.calculate(
    mode: mode,
    step: stepFor(input: input, batch: batch),
    recipe: recipeFor(type, minimum, maximum, base),
    rules: rules,
    profile: AfkWeightProfile(
      maximumWeightLt: 120,
      currentCarriedWeightLt: 10,
      safetyBufferLt: buffer,
    ),
    expectedOutputPerAttempt: expected,
  );

  test(
    'average reserves carry and Keep free once; consumed input is not added',
    () {
      final result = calculate();
      expect(result.availablePayloadLt, 100);
      expect(result.safeAttempts, 400);
      expect(result.startLoadLt, 40);
      expect(result.expectedFinishLoadLt, 100);
      expect(result.finishLoadLt, 100);
      expect(result.finishingTotalLt, 110);
      expect(result.confidence, AfkWeightConfidence.estimated);
      expect(result.usesConservativeOutput, isFalse);
      expect(calculate(buffer: 20).safeAttempts, 360);
    },
  );

  test('heavier starting ingredients remain the limiting endpoint', () {
    final result = calculate(input: 10);
    expect(result.safeAttempts, 100);
    expect(result.startLoadLt, 100);
    expect(result.expectedFinishLoadLt, 25);
    expect(result.peakLoadLt, 100);
  });

  test('processing intermediate uses its recipe type, not enclosing mode', () {
    final result = calculate(mode: CraftMode.cooking);
    expect(result.safeAttempts, 400);
    expect(result.confidence, AfkWeightConfidence.estimated);
  });

  test('mass batches round down without changing per-input yield', () {
    final result = calculate(batch: 212);
    expect(result.safeAttempts, 212);
    expect(result.safeMassBatches, 1);
    expect(result.expectedOutputStack!.perAttemptQuantity, 2.5);
    expect(result.expectedOutputStack!.quantity, 530);
  });

  for (final type in ['cooking', 'alchemy']) {
    test(
      '$type shows mastery average but retains conservative allowance for unknown extras',
      () {
        final avg = type == 'cooking'
            ? cookingExpectedOutput(1900, 1, 4)
            : alchemyExpectedOutput(1900, 1, 4);
        final result = calculate(type: type, expected: avg);
        expect(result.safeAttempts, 250);
        expect(result.outputStack!.perAttemptQuantity, 4);
        expect(result.expectedOutputStack!.perAttemptQuantity, avg);
        expect(result.expectedFinishLoadLt, lessThan(result.finishLoadLt));
        expect(result.usesConservativeOutput, isTrue);
        expect(
          result.warnings,
          contains(AfkWeightWarning.extraOutputRatesUnknown),
        );
        expect(
          result.warnings,
          contains(AfkWeightWarning.byproductsUnmodelled),
        );
      },
    );
  }

  test(
    'higher mastery changes expected main output without invented extras',
    () {
      final low = calculate(
        type: 'cooking',
        expected: cookingExpectedOutput(0, 1, 4),
      );
      final high = calculate(
        type: 'cooking',
        expected: cookingExpectedOutput(2000, 1, 4),
      );
      expect(
        high.expectedOutputStack!.quantity,
        greaterThan(low.expectedOutputStack!.quantity),
      );
      expect(high.safeAttempts, low.safeAttempts);
    },
  );

  test('fixed conversion is recipe-owned and never multiplied by mastery', () {
    final result = calculate(
      type: 'simple alchemy',
      base: 10,
      minimum: 10,
      maximum: 10,
      expected: 10,
    );
    expect(result.safeAttempts, 100);
    expect(result.expectedOutputStack!.quantity, 1000);
    expect(result.confidence, AfkWeightConfidence.exact);
  });

  test('missing/reversed processing bounds keep a conservative fallback', () {
    for (final result in [
      calculate(minimum: null, maximum: null, expected: 10.5),
      calculate(minimum: 4, maximum: 1, expected: 2.5),
    ]) {
      expect(result.usesConservativeOutput, isTrue);
      expect(result.confidence, AfkWeightConfidence.modelled);
    }
    expect(
      calculate(
        minimum: null,
        maximum: null,
        expected: 10.5,
      ).outputStack!.perAttemptQuantity,
      11,
    );
    expect(
      calculate(
        minimum: 4,
        maximum: 1,
        expected: 2.5,
      ).outputStack!.perAttemptQuantity,
      4,
    );
  });

  test('invalid averages are never used for loading or shown as estimates', () {
    for (final value in [0.0, -1.0, double.nan, double.infinity, .5, 5.0]) {
      final result = calculate(expected: value);
      expect(result.safeAttempts, 250);
      expect(result.expectedOutputStack, isNull);
      expect(result.warnings, contains(AfkWeightWarning.invalidOutputEstimate));
    }
  });

  test(
    'partial loads scale both forecasts and capacity without overshooting',
    () {
      final plan = calculator.calculateSessionPlan(
        mode: CraftMode.processing,
        step: stepFor(count: 825, batch: 10),
        recipe: recipeFor('processing', 1, 4, 1),
        rules: rules,
        profile: AfkWeightProfile(maximumWeightLt: 110, safetyBufferLt: 10),
        expectedOutputPerAttempt: 2.5,
        completedAttempts: 400,
      );
      expect(plan.loadCount, 2);
      expect(plan.loads.map((l) => l.attempts), [400, 25]);
      expect(plan.loads.map((l) => l.expectedOutputStack!.quantity), [
        1000,
        63,
      ]);
      expect(plan.loads.last.finishLoadLt, closeTo(6.3, 1e-9));
      expect(plan.loads.last.completedAttemptsAfter, 825);
    },
  );

  test(
    'real Corn Flour matches the reported settings without touching a profile',
    () {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      const assembly = PlannerAssembly();
      final state = ModeState(
        target: 'Corn Flour',
        want: 100,
        bonusTarget: '',
        processingMastery: 1767,
        useMassProcessing: false,
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
      );
      final plan = assembly.build(
        catalog: catalog,
        mode: CraftMode.processing,
        state: state,
      );
      final step = plan.steps.singleWhere((s) => s.name == 'Corn Flour');
      final result = calculator.calculate(
        mode: CraftMode.processing,
        step: step,
        recipe: catalog.processing.items['Corn Flour']!,
        rules: assembly.plannerRules(catalog.supportingData),
        profile: AfkWeightProfile(
          maximumWeightLt: 4024,
          currentCarriedWeightLt: 107.1,
          safetyBufferLt: 100,
          featheryStepsLevel: 5,
        ),
        expectedOutputPerAttempt: step.produced / step.count,
      );
      expect(result.safeAttempts, 19291);
      expect(result.startLoadLt, closeTo(1929.1, 1e-9));
      expect(result.expectedOutputStack!.quantity, 48228);
      expect(result.expectedFinishLoadLt, closeTo(4822.8, 1e-9));
    },
  );
}

Recipe recipeFor(String type, double? low, double? high, double base) => Recipe(
  name: 'Result',
  type: type,
  baseOutput: base,
  group: null,
  method: null,
  ingredients: const [],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: low,
  outputMaximum: high,
);

PlanStep stepFor({double count = 1000, double input = 1, int batch = 1}) =>
    PlanStep(
      name: 'Result',
      index: 0,
      count: count,
      batchCount: count / batch,
      batchSize: batch,
      produced: count * 2.5,
      demand: count * 2.5,
      net: 0,
      depth: 0,
      ingredients: [
        PlanStepIngredient(
          key: 'Raw',
          name: 'Raw',
          original: 'Raw',
          substituteGroup: 'Raw',
          baseName: 'Raw',
          grade: 'base',
          options: const ['Raw'],
          parentName: 'Result',
          need: count * input,
          have: 0,
          missing: count * input,
          craftable: false,
        ),
      ],
    );
