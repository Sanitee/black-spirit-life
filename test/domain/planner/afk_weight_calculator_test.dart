import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/afk_weight_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = AfkWeightCalculator();

  test('Feathery Steps expands the safe penalty threshold', () {
    final result = calculator.calculate(
      mode: CraftMode.cooking,
      step: _step(count: 200, ingredientNeed: 200),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(
        maximumWeightLt: 100,
        safetyBufferLt: 0,
        featheryStepsLevel: 5,
      ),
    );

    expect(result.available, isTrue);
    expect(result.stopWeightLt, 125);
    expect(result.availablePayloadLt, 125);
    expect(result.safeLimitLt, 125);
    expect(result.safeAttempts, 125);
    expect(result.startLoadLt, 125);
    expect(result.finishLoadLt, 125);
  });

  test('ingredient start load can be the limiting endpoint', () {
    final result = calculator.calculate(
      mode: CraftMode.alchemy,
      step: _step(count: 200, ingredientNeed: 400),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': .1}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
    );

    expect(result.safeAttempts, 50);
    expect(result.queuedAttempts, 200);
    expect(result.queueFits, isFalse);
    expect(result.startLoadLt, 100);
    expect(result.finishLoadLt, 5);
    expect(result.peakLoadLt, 100);
  });

  test('maximum safe load is not capped by the queued attempt count', () {
    final result = calculator.calculate(
      mode: CraftMode.cooking,
      step: _step(count: 10, ingredientNeed: 10),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
    );

    expect(result.queuedAttempts, 10);
    expect(result.safeAttempts, 100);
    expect(result.queueFits, isTrue);
    expect(result.ingredientStacks.single.quantity, 100);
    expect(result.outputStack?.quantity, 100);
  });

  test('session plan loads only the current recipe goal below capacity', () {
    final plan = calculator.calculateSessionPlan(
      mode: CraftMode.cooking,
      step: _step(count: 10, ingredientNeed: 20),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
    );

    expect(plan.maximumCapacity.safeAttempts, 50);
    expect(plan.requestedAttempts, 10);
    expect(plan.completedAttempts, 0);
    expect(plan.remainingAttempts, 10);
    expect(plan.plannedAttempts, 10);
    expect(plan.requiresMultipleLoads, isFalse);
    expect(plan.loads, hasLength(1));
    expect(plan.loads.single.number, 1);
    expect(plan.loads.single.attempts, 10);
    expect(plan.loads.single.ingredientStacks.single.quantity, 20);
    expect(plan.loads.single.outputStack.quantity, 10);
    expect(plan.loads.single.startLoadLt, 20);
    expect(plan.loads.single.finishLoadLt, 10);
    expect(plan.loads.single.isFinal, isTrue);
  });

  test('session plan splits a large goal into numbered exact loads', () {
    final plan = calculator.calculateSessionPlan(
      mode: CraftMode.alchemy,
      step: _step(count: 230, ingredientNeed: 230),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
    );

    expect(plan.maxAttemptsPerLoad, 100);
    expect(plan.requiresMultipleLoads, isTrue);
    expect(plan.loads.map((load) => load.number), <int>[1, 2, 3]);
    expect(plan.loads.map((load) => load.attempts), <int>[100, 100, 30]);
    expect(plan.loads.map((load) => load.completedAttemptsAfter), <int>[
      100,
      200,
      230,
    ]);
    expect(plan.loads.map((load) => load.remainingAttemptsAfter), <int>[
      130,
      30,
      0,
    ]);
    expect(
      plan.loads.map((load) => load.ingredientStacks.single.quantity),
      <int>[100, 100, 30],
    );
    expect(plan.plannedAttempts, 230);
  });

  test('session progress rebuilds only remaining numbered loads', () {
    final plan = calculator.calculateSessionPlan(
      mode: CraftMode.cooking,
      step: _step(count: 230, ingredientNeed: 230),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
      completedAttempts: 100,
    );

    expect(plan.requestedAttempts, 230);
    expect(plan.completedAttempts, 100);
    expect(plan.remainingAttempts, 130);
    expect(plan.loads.map((load) => load.number), <int>[2, 3]);
    expect(plan.loads.map((load) => load.attempts), <int>[100, 30]);
    expect(plan.loads.first.completedAttemptsBefore, 100);
    expect(plan.loads.last.completedAttemptsAfter, 230);
    expect(plan.plannedAttempts, 130);
  });

  test('session completion clamps progress and produces no extra load', () {
    final plan = calculator.calculateSessionPlan(
      mode: CraftMode.cooking,
      step: _step(count: 10, ingredientNeed: 10),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
      completedAttempts: 99,
    );

    expect(plan.completedAttempts, 10);
    expect(plan.remainingAttempts, 0);
    expect(plan.complete, isTrue);
    expect(plan.loads, isEmpty);
  });

  test('mass-processing final load never overshoots the recipe goal', () {
    final plan = calculator.calculateSessionPlan(
      mode: CraftMode.processing,
      step: _step(count: 25, ingredientNeed: 25, batchSize: 10),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 20, safetyBufferLt: 0),
    );

    expect(plan.maximumCapacity.safeAttempts, 20);
    expect(plan.maximumCapacity.safeMassBatches, 2);
    expect(plan.loads.map((load) => load.attempts), <int>[20, 5]);
    expect(plan.loads.map((load) => load.massBatches), <int>[2, 1]);
    expect(plan.plannedAttempts, 25);
    expect(plan.loads.last.ingredientStacks.single.quantity, 5);
    expect(plan.loads.last.outputStack.quantity, 5);
  });

  test('unavailable capacity keeps the goal but emits no unsafe loads', () {
    final plan = calculator.calculateSessionPlan(
      mode: CraftMode.alchemy,
      step: _step(count: 10, ingredientNeed: 10),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
    );

    expect(plan.available, isFalse);
    expect(plan.requestedAttempts, 10);
    expect(plan.remainingAttempts, 10);
    expect(plan.plannedAttempts, 0);
    expect(plan.loads, isEmpty);
    expect(
      plan.maximumCapacity.warnings,
      contains(AfkWeightWarning.missingItemWeights),
    );
  });

  test('billion-attempt session stays compact and supports indexed rounds', () {
    const requestedAttempts = 0x7fffffff;
    final plan = calculator.calculateSessionPlan(
      mode: CraftMode.cooking,
      step: _step(
        count: requestedAttempts.toDouble(),
        ingredientNeed: requestedAttempts.toDouble(),
      ),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 1, safetyBufferLt: 0),
    );

    expect(plan.maxAttemptsPerLoad, 1);
    expect(plan.loadCount, requestedAttempts);
    expect(plan.loads.length, requestedAttempts);
    expect(plan.plannedAttempts, requestedAttempts);

    final first = plan.loadAt(0);
    final last = plan.loadAt(requestedAttempts - 1);
    expect(first.number, 1);
    expect(first.attempts, 1);
    expect(first.remainingAttemptsAfter, requestedAttempts - 1);
    expect(last.number, requestedAttempts);
    expect(last.attempts, 1);
    expect(last.completedAttemptsAfter, requestedAttempts);
    expect(last.remainingAttemptsAfter, 0);
    expect(last.isFinal, isTrue);
  });

  test('finished output load can be the limiting endpoint', () {
    final result = calculator.calculate(
      mode: CraftMode.cooking,
      step: _step(count: 200, ingredientNeed: 20),
      recipe: _recipe(outputMaximum: 3),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
    );

    expect(result.safeAttempts, 33);
    expect(result.startLoadLt, 4);
    expect(result.finishLoadLt, 99);
    expect(result.peakLoadLt, 99);
  });

  test('missing profile setup makes the result unavailable', () {
    final result = calculator.calculate(
      mode: CraftMode.alchemy,
      step: _step(count: 10, ingredientNeed: 10),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(),
    );

    expect(result.configured, isFalse);
    expect(result.available, isFalse);
    expect(result.safeAttempts, 0);
    expect(result.confidence, AfkWeightConfidence.unavailable);
    expect(result.warnings, contains(AfkWeightWarning.profileNotConfigured));
  });

  test('missing item weights are reported and never guessed', () {
    final result = calculator.calculate(
      mode: CraftMode.alchemy,
      step: _step(count: 10, ingredientNeed: 10),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
    );

    expect(result.available, isFalse);
    expect(result.safeAttempts, 0);
    expect(result.missingWeightItems, <String>['Meal']);
    expect(result.warnings, contains(AfkWeightWarning.missingItemWeights));
  });

  test('current carry and safety buffer both reduce usable load', () {
    final result = calculator.calculate(
      mode: CraftMode.cooking,
      step: _step(count: 100, ingredientNeed: 100),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(
        maximumWeightLt: 100,
        currentCarriedWeightLt: 10,
        safetyBufferLt: 15,
      ),
    );

    expect(result.safeLimitLt, 75);
    expect(result.stopWeightLt, 85);
    expect(result.safeAttempts, 75);
    expect(result.peakLoadLt, 75);
    expect(result.startingTotalLt, 85);
    expect(result.finishingTotalLt, 85);
    expect(result.peakTotalLt, 85);
  });

  test('missing output maximum uses conservative modelled fallback', () {
    final result = calculator.calculate(
      mode: CraftMode.processing,
      step: _step(count: 100, ingredientNeed: 10),
      recipe: _recipe(baseOutput: 4.2),
      rules: _rules(<String, double>{'Ingredient': .1, 'Meal': 2}),
      profile: AfkWeightProfile(maximumWeightLt: 100, safetyBufferLt: 0),
    );

    expect(result.safeAttempts, 10);
    expect(result.outputStack?.perAttemptQuantity, 5);
    expect(result.confidence, AfkWeightConfidence.modelled);
    expect(
      result.warnings,
      containsAll(<AfkWeightWarning>{
        AfkWeightWarning.modelledOutputMaximum,
        AfkWeightWarning.byproductsUnmodelled,
      }),
    );
  });

  test('each combined inventory stack quantity is rounded up', () {
    final result = calculator.calculate(
      mode: CraftMode.alchemy,
      step: _step(
        count: 10,
        ingredients: <PlanStepIngredient>[
          _ingredient(name: 'Ingredient', need: 1.25),
          _ingredient(name: 'ingredient', need: 1.25),
        ],
      ),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 10, 'Meal': .01}),
      profile: AfkWeightProfile(maximumWeightLt: 20.08, safetyBufferLt: 0),
    );

    expect(result.safeAttempts, 8);
    expect(result.ingredientStacks, hasLength(1));
    expect(result.ingredientStacks.single.perAttemptQuantity, .25);
    expect(result.ingredientStacks.single.quantity, 2);
    expect(result.startLoadLt, 20);
  });

  test('mass processing rounds safe attempts down to whole batches', () {
    final result = calculator.calculate(
      mode: CraftMode.processing,
      step: _step(count: 100, ingredientNeed: 100, batchSize: 10),
      recipe: _recipe(outputMaximum: 1),
      rules: _rules(<String, double>{'Ingredient': 1, 'Meal': 1}),
      profile: AfkWeightProfile(maximumWeightLt: 25, safetyBufferLt: 0),
    );

    expect(result.safeAttempts, 20);
    expect(result.safeMassBatches, 2);
    expect(result.startLoadLt, 20);
    expect(result.finishLoadLt, 20);
  });
}

PlannerRules _rules(Map<String, double> weightsByName) {
  final ids = <String, String>{};
  final weights = <String, double>{};
  var nextId = 1;
  for (final entry in weightsByName.entries) {
    final id = (nextId++).toString();
    ids[entry.key] = id;
    weights[id] = entry.value;
  }
  return PlannerRules(itemWeightIds: ids, itemWeightsLtById: weights);
}

PlanStep _step({
  required double count,
  double? ingredientNeed,
  Iterable<PlanStepIngredient>? ingredients,
  int batchSize = 1,
}) => PlanStep(
  name: 'Meal',
  index: 0,
  count: count,
  batchCount: count / batchSize,
  batchSize: batchSize,
  produced: count,
  demand: count,
  net: 0,
  depth: 0,
  ingredients:
      ingredients ??
      <PlanStepIngredient>[
        _ingredient(name: 'Ingredient', need: ingredientNeed!),
      ],
);

PlanStepIngredient _ingredient({required String name, required double need}) =>
    PlanStepIngredient(
      key: name.toLowerCase(),
      name: name,
      original: name,
      substituteGroup: name,
      baseName: name,
      grade: 'base',
      options: <String>[name],
      parentName: 'Meal',
      need: need,
      have: 0,
      missing: need,
      craftable: false,
    );

Recipe _recipe({double baseOutput = 1, double? outputMaximum}) => Recipe(
  name: 'Meal',
  type: 'material',
  baseOutput: baseOutput,
  group: null,
  method: null,
  ingredients: const <Ingredient>[],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: outputMaximum,
);
