import 'dart:convert';

import '../models/craft_mode.dart';
import '../planner/planner_models.dart' as planning;
import 'inventory_storage.dart';
import 'planner_state.dart';
import 'state_copy.dart';

const craftCreditsKey = 'craftCompletionCredits';
const _historyKey = 'craftCompletionUndo';
const inventoryBatchVersionKey = 'inventoryBatchVersion';

/// Newly crafted stock still counts toward the active queue when the user is
/// ignoring stock owned before starting it. Never count the same output twice.
Map<String, double> craftCredits(ModeState state, {String? target, int? want}) {
  final saved = _contexts(
    state,
  )[_contextKey(target ?? state.target, want ?? state.want)];
  return {
    for (final entry in _amounts(saved).entries)
      entry.key: entry.value.clamp(0, _amount(state.inventory, entry.key)),
  };
}

String _contextKey(String target, int want) => jsonEncode([target, want]);
Map<String, Object?> _contexts(ModeState state) {
  final raw = state.extensions[craftCreditsKey];
  return raw is Map ? Map<String, Object?>.from(raw) : {};
}

/// An inventory correction/import can remove crafted stock. Persist the cap so
/// a later unrelated restock cannot resurrect those old completion credits.
ModeState capCraftCreditsToInventory(ModeState state) {
  final contexts = _contexts(state);
  var changed = false;
  for (final context in contexts.keys.toList()) {
    final credits = _amounts(contexts[context]);
    for (final item in credits.keys.toList()) {
      final amount = _amount(state.inventory, item);
      if (credits[item]! > amount) {
        changed = true;
        credits[item] = amount;
      }
    }
    contexts[context] = credits;
  }
  return changed
      ? state.copyWith(
          extensions: {...state.extensions, craftCreditsKey: contexts},
        )
      : state;
}

planning.PlanStep scaleCraftStep(planning.PlanStep step, double attempts) {
  final factor = attempts / step.count;
  return planning.PlanStep(
    name: step.name,
    index: step.index,
    count: attempts,
    batchCount: (attempts / step.batchSize).ceilToDouble(),
    batchSize: step.batchSize,
    produced: step.produced * factor,
    demand: step.demand,
    net: step.net,
    depth: step.depth,
    ingredients: [
      for (final item in step.ingredients)
        planning.PlanStepIngredient(
          key: item.key,
          name: item.name,
          original: item.original,
          substituteGroup: item.substituteGroup,
          baseName: item.baseName,
          grade: item.grade,
          options: item.options,
          parentName: item.parentName,
          need: item.need * factor,
          have: item.have,
          missing: (item.need * factor - item.have).clamp(0, double.infinity),
          craftable: item.craftable,
        ),
    ],
  );
}

/// One atomic persisted change: inventory, queue credit/mark, AFK progress and
/// the receipt needed to undo it. Receipts store actual clamped stock changes.
PlannerState recordCraftCompletion({
  required PlannerState document,
  required CraftMode mode,
  required planning.PlanStep step,
  required String target,
  required int want,
  required bool markComplete,
  bool roundIngredients = false,
  AfkCraftProgress? progress,
}) {
  final before = document.forMode(mode);
  final deltas = <String, double>{};
  void add(String name, double quantity) {
    final key = _key(deltas, name);
    deltas[key] = (deltas[key] ?? 0) + quantity;
  }

  for (final item in step.ingredients) {
    add(item.name, -item.need);
  }
  if (roundIngredients) {
    for (final name in deltas.keys.toList()) {
      deltas[name] = -(-deltas[name]!).ceilToDouble();
    }
  }
  add(step.name, step.produced);
  var adjusted = applySharedInventoryDeltas(document, deltas);
  final activeContext = _contextKey(target, want);
  for (final craftMode in CraftMode.values) {
    final source = document.forMode(craftMode);
    final contexts = _contexts(source);
    if (craftMode == mode) {
      contexts.putIfAbsent(activeContext, () => <String, double>{});
    }
    for (final context in contexts.keys.toList()) {
      final credits = _amounts(contexts[context]);
      for (final delta in deltas.entries) {
        if (delta.value > 0 &&
            (craftMode != mode || context != activeContext)) {
          continue;
        }
        final key = _key(credits, delta.key);
        final existing = (credits[key] ?? 0).clamp(
          0.0,
          _amount(source.inventory, key),
        );
        final next = (existing + delta.value).clamp(0.0, double.infinity);
        if (next > 0) {
          credits[key] = next;
        } else {
          credits.remove(key);
        }
      }
      contexts[context] = credits;
    }
    while (contexts.length > 32) {
      contexts.remove(contexts.keys.firstWhere((key) => key != activeContext));
    }
    if (contexts.isNotEmpty) {
      final current = adjusted.forMode(craftMode);
      adjusted = _withMode(
        adjusted,
        craftMode,
        current.copyWith(
          extensions: {...current.extensions, craftCreditsKey: contexts},
        ),
      );
    }
  }
  final after = adjusted.forMode(mode);
  final completed = Set<String>.of(after.completedSteps);
  if (markComplete) completed.add(step.name);
  final progressMap = Map<String, AfkCraftProgress>.of(after.afkCraftProgress);
  if (progress != null) {
    progressMap.remove(progress.stepKey);
    progressMap[progress.stepKey] = progress;
    while (progressMap.length > AfkCraftProgress.maximumStoredStepsPerMode) {
      progressMap.remove(progressMap.keys.first);
    }
  }
  final nextMode = after.copyWith(
    completedSteps: completed,
    afkCraftProgress: progressMap,
  );
  final receipt = <String, Object?>{
    'mode': mode.key,
    'recipe': step.name,
    'target': before.target,
    'want': before.want,
    'inventoryBefore': {
      for (final name in deltas.keys) name: _amount(before.inventory, name),
    },
    'inventoryAfter': {
      for (final name in deltas.keys) name: _amount(after.inventory, name),
    },
    'markedBefore': _marked(before, step.name),
    'markedAfter': _marked(nextMode, step.name),
    'creditsBefore': {
      for (final value in CraftMode.values)
        value.key: document.forMode(value).extensions[craftCreditsKey],
    },
    'creditsAfter': {
      for (final value in CraftMode.values)
        value.key: adjusted.forMode(value).extensions[craftCreditsKey],
    },
    if (progress != null) ...{
      'progressKey': progress.stepKey,
      'progressBefore': before.afkCraftProgress[progress.stepKey]?.toJson(),
      'progressAfter': progress.toJson(),
    },
  };
  final history = [..._history(document), receipt];
  return _withMode(adjusted, mode, nextMode).copyWith(
    extensions: {
      ...document.extensions,
      _historyKey: history.skip((history.length - 100).clamp(0, 100)).toList(),
    },
  );
}

Map? latestCraftCompletion(PlannerState document, CraftMode mode) {
  final history = _history(document);
  if (history.isEmpty || history.last['mode'] != mode.key) return null;
  return history.last;
}

/// Refuse an undo that would overwrite a later manual edit. Unrelated settings,
/// inventory items and other modes are never restored from an old snapshot.
PlannerState? undoCraftCompletion(PlannerState document, CraftMode mode) {
  final receipt = latestCraftCompletion(document, mode);
  if (receipt == null) return null;
  final current = document.forMode(mode);
  final recipe = receipt['recipe'];
  if (recipe is! String ||
      current.target != receipt['target'] ||
      current.want != receipt['want'] ||
      _marked(current, recipe) != receipt['markedAfter']) {
    return null;
  }
  final oldCredits = receipt['creditsBefore'];
  final newCredits = receipt['creditsAfter'];
  if (oldCredits is! Map || newCredits is! Map) return null;
  for (final value in CraftMode.values) {
    if (!_same(
      document.forMode(value).extensions[craftCreditsKey],
      newCredits[value.key],
    )) {
      return null;
    }
  }
  final before = _amounts(receipt['inventoryBefore']);
  final after = _amounts(receipt['inventoryAfter']);
  if (before.isEmpty || before.length != after.length) return null;
  for (final entry in after.entries) {
    if (!before.containsKey(entry.key) ||
        (_amount(current.inventory, entry.key) - entry.value).abs() >
            0.000001) {
      return null;
    }
  }
  final progressKey = receipt['progressKey'];
  final progress = Map<String, AfkCraftProgress>.of(current.afkCraftProgress);
  if (progressKey is String) {
    if (!_same(progress[progressKey]?.toJson(), receipt['progressAfter'])) {
      return null;
    }
    final saved = receipt['progressBefore'];
    if (saved == null) {
      progress.remove(progressKey);
    } else {
      final restored = _progress(saved);
      if (restored == null) return null;
      progress[progressKey] = restored;
    }
  }
  var restored = setSharedInventoryAmounts(document, before);
  for (final value in CraftMode.values) {
    final state = restored.forMode(value);
    final extensions = Map<String, Object?>.of(state.extensions);
    if (oldCredits[value.key] == null) {
      extensions.remove(craftCreditsKey);
    } else {
      extensions[craftCreditsKey] = oldCredits[value.key];
    }
    restored = _withMode(
      restored,
      value,
      state.copyWith(extensions: extensions),
    );
  }
  final completed = Set<String>.of(current.completedSteps)
    ..removeWhere((name) => _fold(name) == _fold(recipe));
  if (receipt['markedBefore'] == true) completed.add(recipe);
  final history = _history(document)..removeLast();
  return _withMode(
    restored,
    mode,
    restored
        .forMode(mode)
        .copyWith(completedSteps: completed, afkCraftProgress: progress),
  ).copyWith(extensions: {...document.extensions, _historyKey: history});
}

List<Map> _history(PlannerState document) {
  final raw = document.extensions[_historyKey];
  return raw is List ? raw.whereType<Map>().toList() : [];
}

AfkCraftProgress? _progress(Object? raw) {
  if (raw is! Map) return null;
  try {
    return AfkCraftProgress(
      stepKey: raw['stepKey'] as String,
      targetName: raw['targetName'] as String,
      targetAmount: raw['targetAmount'] as int,
      recipeName: raw['recipeName'] as String,
      planSignature: raw['planSignature'] as String,
      totalAttempts: raw['totalAttempts'] as int,
      attemptsPerRound: raw['attemptsPerRound'] as int,
      completedAttempts: raw['completedAttempts'] as int,
      extensions: Map<String, Object?>.from(raw['extensions'] as Map? ?? {}),
    );
  } on TypeError {
    return null;
  }
}

Map<String, double> _amounts(Object? raw) => raw is Map
    ? {
        for (final entry in raw.entries)
          if (entry.key is String &&
              entry.value is num &&
              (entry.value as num).isFinite &&
              (entry.value as num) >= 0)
            entry.key as String: (entry.value as num).toDouble(),
      }
    : {};

bool _same(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);
String _fold(String name) => name.trim().toLowerCase();
String _key(Map<String, double> values, String name) => values.keys.firstWhere(
  (key) => _fold(key) == _fold(name),
  orElse: () => name.trim(),
);
double _amount(Map<String, double> values, String name) =>
    values[_key(values, name)] ?? 0;
bool _marked(ModeState state, String name) =>
    state.completedSteps.any((entry) => _fold(entry) == _fold(name));
PlannerState _withMode(PlannerState state, CraftMode mode, ModeState value) =>
    switch (mode) {
      CraftMode.alchemy => state.copyWith(alchemy: value),
      CraftMode.cooking => state.copyWith(cooking: value),
      CraftMode.processing => state.copyWith(processing: value),
    };
