import 'dart:collection';
import 'dart:math' as math;

import '../models/catalog_models.dart';
import '../models/craft_mode.dart';
import '../state/planner_state.dart';
import 'planner_models.dart';

/// How directly the calculator can support its output-load estimate.
enum AfkWeightConfidence {
  /// The recipe supplies a positive recorded maximum output per attempt.
  exact,

  /// The recipe has no recorded maximum, so a conservative fallback is used.
  modelled,

  /// Required setup or item-weight data is missing.
  unavailable,
}

/// Structured caveats that presentation code can explain without parsing text.
enum AfkWeightWarning {
  profileNotConfigured,
  noUsableCapacity,
  invalidPlanStep,
  missingItemWeights,
  modelledOutputMaximum,
  byproductsUnmodelled,
}

enum AfkLoadStackKind { ingredient, output }

/// One integer inventory stack at a calculated load endpoint.
final class AfkLoadStack {
  const AfkLoadStack({
    required this.kind,
    required this.itemName,
    required this.perAttemptQuantity,
    required this.quantity,
    required this.unitWeightLt,
  });

  final AfkLoadStackKind kind;
  final String itemName;
  final double perAttemptQuantity;
  final int quantity;
  final double unitWeightLt;

  double get loadLt => quantity * unitWeightLt;
}

/// Immutable AFK load recommendation for one queued recipe step.
///
/// [availablePayloadLt] is the payload capacity remaining after the configured
/// current carry, safety buffer, and Feathery Steps threshold adjustment.
/// Consequently [startLoadLt], [finishLoadLt], and [peakLoadLt] describe only
/// the additional recipe payload. The corresponding `*TotalLt` getters include
/// the character's pre-existing load for direct display against [stopWeightLt].
final class AfkWeightCalculation {
  AfkWeightCalculation({
    required this.configured,
    required this.available,
    required this.queuedAttempts,
    required this.queueFits,
    required this.safeAttempts,
    required this.safeMassBatches,
    required this.availablePayloadLt,
    required this.currentCarriedWeightLt,
    required this.stopWeightLt,
    required this.startLoadLt,
    required this.finishLoadLt,
    required this.peakLoadLt,
    required Iterable<AfkLoadStack> ingredientStacks,
    required this.outputStack,
    required this.confidence,
    required Iterable<AfkWeightWarning> warnings,
    required Iterable<String> missingWeightItems,
  }) : ingredientStacks = List<AfkLoadStack>.unmodifiable(ingredientStacks),
       warnings = Set<AfkWeightWarning>.unmodifiable(warnings),
       missingWeightItems = List<String>.unmodifiable(missingWeightItems);

  final bool configured;
  final bool available;
  final int queuedAttempts;
  final bool queueFits;
  final int safeAttempts;
  final int safeMassBatches;
  final double availablePayloadLt;
  final double currentCarriedWeightLt;
  final double stopWeightLt;
  final double startLoadLt;
  final double finishLoadLt;
  final double peakLoadLt;
  final List<AfkLoadStack> ingredientStacks;
  final AfkLoadStack? outputStack;
  final AfkWeightConfidence confidence;
  final Set<AfkWeightWarning> warnings;
  final List<String> missingWeightItems;

  /// Compatibility-friendly shorthand for [availablePayloadLt].
  double get safeLimitLt => availablePayloadLt;

  double get startingTotalLt => currentCarriedWeightLt + startLoadLt;

  double get finishingTotalLt => currentCarriedWeightLt + finishLoadLt;

  double get peakTotalLt => currentCarriedWeightLt + peakLoadLt;

  bool get isLimited => available && safeAttempts == 0;

  bool get isIncomplete =>
      confidence != AfkWeightConfidence.exact ||
      warnings.contains(AfkWeightWarning.byproductsUnmodelled);
}

/// One numbered, goal-sized load in an AFK crafting session.
///
/// Unlike [AfkWeightCalculation.ingredientStacks], these stacks contain only
/// what is needed for this load. [completedAttemptsAfter] and
/// [remainingAttemptsAfter] let presentation code persist progress as an
/// attempt count instead of tying it to a particular capacity or list shape.
final class AfkWeightSessionLoad {
  AfkWeightSessionLoad({
    required this.number,
    required this.attempts,
    required this.massBatches,
    required this.completedAttemptsBefore,
    required this.completedAttemptsAfter,
    required this.remainingAttemptsAfter,
    required this.startLoadLt,
    required this.finishLoadLt,
    required this.peakLoadLt,
    required Iterable<AfkLoadStack> ingredientStacks,
    required this.outputStack,
  }) : ingredientStacks = List<AfkLoadStack>.unmodifiable(ingredientStacks);

  final int number;
  final int attempts;
  final int massBatches;
  final int completedAttemptsBefore;
  final int completedAttemptsAfter;
  final int remainingAttemptsAfter;
  final double startLoadLt;
  final double finishLoadLt;
  final double peakLoadLt;
  final List<AfkLoadStack> ingredientStacks;
  final AfkLoadStack outputStack;

  bool get isFinal => remainingAttemptsAfter == 0;
}

/// A goal-aware AFK session without losing the separate capacity answer.
///
/// [maximumCapacity] answers "how much could this character carry?" while
/// [loads] answers "what should be carried to finish the recipe goal?". The
/// latter never exceeds [requestedAttempts], even when capacity is larger.
final class AfkWeightSessionPlan {
  AfkWeightSessionPlan._({
    required this.maximumCapacity,
    required this.requestedAttempts,
    required this.completedAttempts,
    required this._massBatchSize,
  });

  final AfkWeightCalculation maximumCapacity;
  final int requestedAttempts;
  final int completedAttempts;
  final int _massBatchSize;

  int get remainingAttempts => requestedAttempts - completedAttempts;

  int get maxAttemptsPerLoad => maximumCapacity.safeAttempts;

  /// Number of remaining numbered loads without materializing them.
  int get loadCount {
    final capacity = maxAttemptsPerLoad;
    if (!available || capacity <= 0 || remainingAttempts <= 0) return 0;
    final fullLoads = remainingAttempts ~/ capacity;
    return fullLoads + (remainingAttempts % capacity == 0 ? 0 : 1);
  }

  /// Compatibility-friendly, immutable lazy list of the remaining loads.
  ///
  /// Its length and indexed access are O(1), so even a very large recipe goal
  /// does not allocate one Dart object per round. UI code should render only
  /// the visible range or use [loadAt] directly rather than eagerly calling
  /// `toList()` for an unbounded goal.
  List<AfkWeightSessionLoad> get loads => _AfkWeightSessionLoadList(this);

  AfkWeightSessionLoad loadAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', loadCount);
    final capacity = maxAttemptsPerLoad;
    final attemptsBeforeThisLoad = completedAttempts + index * capacity;
    final attempts = math.min(
      capacity,
      requestedAttempts - attemptsBeforeThisLoad,
    );
    final ingredientStacks = <AfkLoadStack>[
      for (final stack in maximumCapacity.ingredientStacks)
        AfkLoadStack(
          kind: stack.kind,
          itemName: stack.itemName,
          perAttemptQuantity: stack.perAttemptQuantity,
          quantity: (stack.perAttemptQuantity * attempts).ceil(),
          unitWeightLt: stack.unitWeightLt,
        ),
    ];
    final maximumOutputStack = maximumCapacity.outputStack!;
    final outputStack = AfkLoadStack(
      kind: maximumOutputStack.kind,
      itemName: maximumOutputStack.itemName,
      perAttemptQuantity: maximumOutputStack.perAttemptQuantity,
      quantity: (maximumOutputStack.perAttemptQuantity * attempts).ceil(),
      unitWeightLt: maximumOutputStack.unitWeightLt,
    );
    final startLoadLt = ingredientStacks.fold<double>(
      0,
      (total, stack) => total + stack.loadLt,
    );
    final finishLoadLt = outputStack.loadLt;
    final completedAfter = attemptsBeforeThisLoad + attempts;
    return AfkWeightSessionLoad(
      number: completedAttempts ~/ capacity + index + 1,
      attempts: attempts,
      massBatches: _massBatchSize > 1 ? (attempts / _massBatchSize).ceil() : 0,
      completedAttemptsBefore: attemptsBeforeThisLoad,
      completedAttemptsAfter: completedAfter,
      remainingAttemptsAfter: requestedAttempts - completedAfter,
      startLoadLt: startLoadLt,
      finishLoadLt: finishLoadLt,
      peakLoadLt: math.max(startLoadLt, finishLoadLt),
      ingredientStacks: ingredientStacks,
      outputStack: outputStack,
    );
  }

  int get plannedAttempts => loadCount == 0 ? 0 : remainingAttempts;

  bool get available => maximumCapacity.available;

  bool get complete => remainingAttempts == 0;

  bool get requiresMultipleLoads => loadCount > 1;
}

final class _AfkWeightSessionLoadList extends ListBase<AfkWeightSessionLoad> {
  _AfkWeightSessionLoadList(this.plan);

  final AfkWeightSessionPlan plan;

  @override
  int get length => plan.loadCount;

  @override
  set length(int value) => throw UnsupportedError('AFK loads are immutable.');

  @override
  AfkWeightSessionLoad operator [](int index) => plan.loadAt(index);

  @override
  void operator []=(int index, AfkWeightSessionLoad value) =>
      throw UnsupportedError('AFK loads are immutable.');
}

/// Calculates the maximum conservative AFK load for the selected queue recipe.
///
/// Only the selected ingredient stacks in [step] are considered. Their
/// per-attempt quantities are recovered from `need / count`, then each final
/// inventory stack is rounded up independently. Both the fully loaded start
/// and fully produced finish endpoints must fit. The queued count is reported
/// by the result but never caps the maximum safe recommendation.
final class AfkWeightCalculator {
  const AfkWeightCalculator();

  /// Splits the current recipe goal into exact, numbered safe loads.
  ///
  /// [PlanStep.count] is the planner's remaining number of recipe attempts and
  /// is rounded up exactly as [calculate] reports it. [completedAttempts] is
  /// optional progress already made against that goal; callers can save the
  /// `completedAttemptsAfter` value from a checked load and rebuild the
  /// remaining list without persisting weight-dependent load boundaries.
  ///
  /// Processing capacity remains rounded down to a whole mass-processing
  /// batch. A smaller final goal load is allowed so the helper never asks the
  /// player to process more than the planner requested.
  AfkWeightSessionPlan calculateSessionPlan({
    required CraftMode mode,
    required PlanStep step,
    required Recipe recipe,
    required PlannerRules rules,
    required AfkWeightProfile profile,
    int completedAttempts = 0,
  }) {
    final maximumCapacity = calculate(
      mode: mode,
      step: step,
      recipe: recipe,
      rules: rules,
      profile: profile,
    );
    final requestedAttempts = maximumCapacity.queuedAttempts;
    final normalizedCompletedAttempts = completedAttempts.clamp(
      0,
      requestedAttempts,
    );
    final massBatchSize = mode == CraftMode.processing && step.batchSize > 1
        ? step.batchSize
        : 1;
    return AfkWeightSessionPlan._(
      maximumCapacity: maximumCapacity,
      requestedAttempts: requestedAttempts,
      completedAttempts: normalizedCompletedAttempts,
      massBatchSize: massBatchSize,
    );
  }

  AfkWeightCalculation calculate({
    required CraftMode mode,
    required PlanStep step,
    required Recipe recipe,
    required PlannerRules rules,
    required AfkWeightProfile profile,
  }) {
    final configured = profile.isConfigured;
    final queuedAttempts = step.count.isFinite && step.count > 0
        ? step.count.ceil()
        : 0;
    final availablePayloadLt = _finiteNonnegative(profile.safeLimitLt);
    final currentCarriedWeightLt = _finiteNonnegative(
      profile.currentCarriedWeightLt,
    );
    final stopWeightLt = _finiteNonnegative(
      profile.penaltyThresholdLt - profile.safetyBufferLt,
    );
    final warnings = <AfkWeightWarning>{AfkWeightWarning.byproductsUnmodelled};

    if (!configured) {
      warnings.add(AfkWeightWarning.profileNotConfigured);
      return _unavailable(
        configured: false,
        queuedAttempts: queuedAttempts,
        availablePayloadLt: availablePayloadLt,
        currentCarriedWeightLt: currentCarriedWeightLt,
        stopWeightLt: stopWeightLt,
        warnings: warnings,
      );
    }
    if (availablePayloadLt <= 0) {
      warnings.add(AfkWeightWarning.noUsableCapacity);
      return _unavailable(
        configured: true,
        queuedAttempts: queuedAttempts,
        availablePayloadLt: availablePayloadLt,
        currentCarriedWeightLt: currentCarriedWeightLt,
        stopWeightLt: stopWeightLt,
        warnings: warnings,
      );
    }
    if (!step.count.isFinite || step.count <= 0) {
      warnings.add(AfkWeightWarning.invalidPlanStep);
      return _unavailable(
        configured: true,
        queuedAttempts: queuedAttempts,
        availablePayloadLt: availablePayloadLt,
        currentCarriedWeightLt: currentCarriedWeightLt,
        stopWeightLt: stopWeightLt,
        warnings: warnings,
      );
    }

    final ingredientQuantities = <String, double>{};
    final ingredientNames = <String, String>{};
    for (final ingredient in step.ingredients) {
      final perAttempt = ingredient.need / step.count;
      if (!perAttempt.isFinite || perAttempt < 0) {
        warnings.add(AfkWeightWarning.invalidPlanStep);
        return _unavailable(
          configured: true,
          queuedAttempts: queuedAttempts,
          availablePayloadLt: availablePayloadLt,
          currentCarriedWeightLt: currentCarriedWeightLt,
          stopWeightLt: stopWeightLt,
          warnings: warnings,
        );
      }
      if (perAttempt == 0) continue;
      final foldedName = ingredient.name.trim().toLowerCase();
      if (foldedName.isEmpty) {
        warnings.add(AfkWeightWarning.invalidPlanStep);
        return _unavailable(
          configured: true,
          queuedAttempts: queuedAttempts,
          availablePayloadLt: availablePayloadLt,
          currentCarriedWeightLt: currentCarriedWeightLt,
          stopWeightLt: stopWeightLt,
          warnings: warnings,
        );
      }
      ingredientNames.putIfAbsent(foldedName, () => ingredient.name.trim());
      ingredientQuantities.update(
        foldedName,
        (current) => current + perAttempt,
        ifAbsent: () => perAttempt,
      );
    }

    final outputName = recipe.name.trim();
    final explicitOutputMaximum = recipe.outputMaximum;
    final hasExplicitOutputMaximum =
        explicitOutputMaximum != null &&
        explicitOutputMaximum.isFinite &&
        explicitOutputMaximum > 0;
    final outputPerAttempt = hasExplicitOutputMaximum
        ? explicitOutputMaximum
        : math.max(4, recipe.baseOutput.ceil()).toDouble();
    final confidence = hasExplicitOutputMaximum
        ? AfkWeightConfidence.exact
        : AfkWeightConfidence.modelled;
    if (!hasExplicitOutputMaximum) {
      warnings.add(AfkWeightWarning.modelledOutputMaximum);
    }

    final missingWeights = <String>{};
    final ingredientWeights = <String, double>{};
    for (final entry in ingredientNames.entries) {
      final weight = rules.itemWeightLtFor(entry.value);
      if (weight == null) {
        missingWeights.add(entry.value);
      } else {
        ingredientWeights[entry.key] = weight;
      }
    }
    final outputWeight = outputName.isEmpty
        ? null
        : rules.itemWeightLtFor(outputName);
    if (outputWeight == null) missingWeights.add(outputName);

    if (missingWeights.isNotEmpty) {
      warnings.add(AfkWeightWarning.missingItemWeights);
      return _unavailable(
        configured: true,
        queuedAttempts: queuedAttempts,
        availablePayloadLt: availablePayloadLt,
        currentCarriedWeightLt: currentCarriedWeightLt,
        stopWeightLt: stopWeightLt,
        warnings: warnings,
        missingWeightItems: missingWeights.where((name) => name.isNotEmpty),
      );
    }
    final resolvedOutputWeight = outputWeight!;

    final massBatchSize = mode == CraftMode.processing && step.batchSize > 1
        ? step.batchSize
        : 1;
    final startRateLt = ingredientQuantities.entries.fold<double>(
      0,
      (total, entry) => total + entry.value * ingredientWeights[entry.key]!,
    );
    final finishRateLt = outputPerAttempt * resolvedOutputWeight;
    final peakRateLt = math.max(startRateLt, finishRateLt);
    if (!peakRateLt.isFinite || peakRateLt <= 0) {
      warnings.add(AfkWeightWarning.invalidPlanStep);
      return _unavailable(
        configured: true,
        queuedAttempts: queuedAttempts,
        availablePayloadLt: availablePayloadLt,
        currentCarriedWeightLt: currentCarriedWeightLt,
        stopWeightLt: stopWeightLt,
        warnings: warnings,
      );
    }
    final continuousUpperBound = availablePayloadLt / peakRateLt;
    if (!continuousUpperBound.isFinite || continuousUpperBound < 0) {
      warnings.add(AfkWeightWarning.invalidPlanStep);
      return _unavailable(
        configured: true,
        queuedAttempts: queuedAttempts,
        availablePayloadLt: availablePayloadLt,
        currentCarriedWeightLt: currentCarriedWeightLt,
        stopWeightLt: stopWeightLt,
        warnings: warnings,
      );
    }
    // Ceilings can only increase endpoint loads, so one attempt beyond the
    // continuous ratio is a finite, guaranteed upper bound for binary search.
    final maximumAttempts = continuousUpperBound.floor() + 1;
    final maximumUnits = maximumAttempts ~/ massBatchSize;
    var low = 0;
    var high = maximumUnits;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      final attempts = middle * massBatchSize;
      final loads = _loadsForAttempts(
        attempts: attempts,
        ingredientQuantities: ingredientQuantities,
        ingredientWeights: ingredientWeights,
        outputPerAttempt: outputPerAttempt,
        outputWeightLt: resolvedOutputWeight,
      );
      if (loads.peakLt <= availablePayloadLt) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }

    final safeAttempts = low * massBatchSize;
    final loads = _loadsForAttempts(
      attempts: safeAttempts,
      ingredientQuantities: ingredientQuantities,
      ingredientWeights: ingredientWeights,
      outputPerAttempt: outputPerAttempt,
      outputWeightLt: resolvedOutputWeight,
    );
    final ingredientStacks = <AfkLoadStack>[
      for (final entry in ingredientQuantities.entries)
        AfkLoadStack(
          kind: AfkLoadStackKind.ingredient,
          itemName: ingredientNames[entry.key]!,
          perAttemptQuantity: entry.value,
          quantity: (entry.value * safeAttempts).ceil(),
          unitWeightLt: ingredientWeights[entry.key]!,
        ),
    ];
    final outputStack = AfkLoadStack(
      kind: AfkLoadStackKind.output,
      itemName: outputName,
      perAttemptQuantity: outputPerAttempt,
      quantity: (outputPerAttempt * safeAttempts).ceil(),
      unitWeightLt: resolvedOutputWeight,
    );

    return AfkWeightCalculation(
      configured: true,
      available: true,
      queuedAttempts: queuedAttempts,
      queueFits: queuedAttempts <= safeAttempts,
      safeAttempts: safeAttempts,
      safeMassBatches: mode == CraftMode.processing && step.batchSize > 1
          ? safeAttempts ~/ step.batchSize
          : 0,
      availablePayloadLt: availablePayloadLt,
      currentCarriedWeightLt: currentCarriedWeightLt,
      stopWeightLt: stopWeightLt,
      startLoadLt: loads.startLt,
      finishLoadLt: loads.finishLt,
      peakLoadLt: loads.peakLt,
      ingredientStacks: ingredientStacks,
      outputStack: outputStack,
      confidence: confidence,
      warnings: warnings,
      missingWeightItems: const <String>[],
    );
  }
}

AfkWeightCalculation _unavailable({
  required bool configured,
  required int queuedAttempts,
  required double availablePayloadLt,
  required double currentCarriedWeightLt,
  required double stopWeightLt,
  required Iterable<AfkWeightWarning> warnings,
  Iterable<String> missingWeightItems = const <String>[],
}) => AfkWeightCalculation(
  configured: configured,
  available: false,
  queuedAttempts: queuedAttempts,
  queueFits: false,
  safeAttempts: 0,
  safeMassBatches: 0,
  availablePayloadLt: availablePayloadLt,
  currentCarriedWeightLt: currentCarriedWeightLt,
  stopWeightLt: stopWeightLt,
  startLoadLt: 0,
  finishLoadLt: 0,
  peakLoadLt: 0,
  ingredientStacks: const <AfkLoadStack>[],
  outputStack: null,
  confidence: AfkWeightConfidence.unavailable,
  warnings: warnings,
  missingWeightItems: missingWeightItems,
);

_EndpointLoads _loadsForAttempts({
  required int attempts,
  required Map<String, double> ingredientQuantities,
  required Map<String, double> ingredientWeights,
  required double outputPerAttempt,
  required double outputWeightLt,
}) {
  var startLt = 0.0;
  for (final entry in ingredientQuantities.entries) {
    startLt += (entry.value * attempts).ceil() * ingredientWeights[entry.key]!;
  }
  final finishLt = (outputPerAttempt * attempts).ceil() * outputWeightLt;
  return _EndpointLoads(startLt: startLt, finishLt: finishLt);
}

final class _EndpointLoads {
  const _EndpointLoads({required this.startLt, required this.finishLt});

  final double startLt;
  final double finishLt;

  double get peakLt => math.max(startLt, finishLt);
}

double _finiteNonnegative(double value) =>
    value.isFinite && value > 0 ? value : 0;
