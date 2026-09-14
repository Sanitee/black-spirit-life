import 'dart:math' as math;

import 'lodging_data.dart';
import 'storage_house_planner.dart';

TownHouseInvestment solveTownHouseInvestmentRequest(
  (LodgingTown, List<TownHouseGoal>, Set<String>) request,
) => TownHouseInvestmentPlanner.solve(
  town: request.$1,
  goals: request.$2,
  owned: request.$3,
);

/// Additional capacity only. Existing houses are never repurposed by a plan.
final class TownHouseGoal {
  const TownHouseGoal(this.typeId, this.amount, {this.minimumLevel = 1});
  final int typeId;
  final int amount;
  final int minimumLevel;
}

final class TownHousePlanTooComplex implements Exception {
  const TownHousePlanTooComplex();
}

final class TownHouseInvestment {
  const TownHouseInvestment({
    required this.usages,
    required this.requiredHouseIds,
    required this.addedCapacity,
    required this.cp,
    required this.isFeasible,
  });
  final Map<String, int> usages;
  final Set<String> requiredHouseIds;
  final Map<int, int> addedCapacity;
  final int cp;
  final bool isFeasible;
}

int houseUseCapacity(LodgingHouse house, int typeId) => switch (typeId) {
  1 => house.lodgingSpaces,
  2 => storageSlotsForHouse(house),
  3 => house.usagesByTypeId[3]?.level ?? 0,
  _ => house.supportsUsage(typeId) ? 1 : 0,
};

/// Sparse, prerequisite-closed tree knapsack. A house gets exactly one use;
/// shared prerequisites are charged once. Run away from the rendering isolate.
/// Target-capped keys bound the state space without imposing arbitrary UI caps.
abstract final class TownHouseInvestmentPlanner {
  static TownHouseInvestment solve({
    required LodgingTown town,
    required List<TownHouseGoal> goals,
    Set<String> owned = const {},
  }) {
    if (goals.any((g) => g.typeId < 0 || g.amount < 0 || g.minimumLevel < 1) ||
        goals.map((g) => g.typeId).toSet().length != goals.length) {
      throw ArgumentError('Goals require unique uses and nonnegative amounts.');
    }
    final active = goals.where((g) => g.amount > 0).toList();
    for (final goal in active) {
      final available = town.houses
          .where(
            (h) =>
                !owned.contains(h.id) &&
                (h.usagesByTypeId[goal.typeId]?.level ?? 0) >=
                    goal.minimumLevel,
          )
          .fold(0, (n, h) => n + houseUseCapacity(h, goal.typeId));
      if (goal.amount > available) {
        return TownHouseInvestment(
          usages: const {},
          requiredHouseIds: const {},
          addedCapacity: {for (final g in active) g.typeId: 0},
          cp: 0,
          isFeasible: false,
        );
      }
    }
    var combinations = 0;
    final zero = List<int>.filled(active.length, 0);
    final empty = _Portfolio(0, zero, const {}, const {});
    String key(List<int> values) => List.generate(
      active.length,
      (i) => math.min(values[i], active[i].amount),
    ).join(',');
    final zeroKey = key(zero);
    Map<String, _Portfolio> merge(
      Map<String, _Portfolio> a,
      Map<String, _Portfolio> b,
    ) {
      final out = <String, _Portfolio>{};
      for (final x in a.values) {
        for (final y in b.values) {
          // Exact multi-use planning is combinatorial. Bound memory/work, not
          // the user's target, and never return an approximation as optimal.
          if (++combinations > 8000000 || out.length > 75000) {
            throw const TownHousePlanTooComplex();
          }
          final capacity = List.generate(
            active.length,
            (i) => x.capacity[i] + y.capacity[i],
          );
          final k = key(capacity);
          final old = out[k];
          final cost = x.cp + y.cp;
          if (old != null && cost > old.cp) continue;
          final next = _Portfolio(
            cost,
            capacity,
            {...x.usages, ...y.usages},
            {...x.required, ...y.required},
          );
          if (old == null || _better(next, old)) out[k] = next;
        }
      }
      return out;
    }

    final children = <String?, List<LodgingHouse>>{};
    for (final house in town.houses) {
      children.putIfAbsent(house.prerequisiteHouseId, () => []).add(house);
    }
    for (final list in children.values) {
      list.sort((a, b) => a.sourceKey.compareTo(b.sourceKey));
    }
    Map<String, _Portfolio> subtree(LodgingHouse house) {
      final cost = owned.contains(house.id) ? 0 : house.contributionPoints;
      final acquired = _Portfolio(cost, zero, const {}, {house.id});
      var options = <String, _Portfolio>{zeroKey: acquired};
      if (!owned.contains(house.id)) {
        for (var i = 0; i < active.length; i++) {
          final goal = active[i];
          final use = house.usagesByTypeId[goal.typeId];
          if (use == null || use.level < goal.minimumLevel) continue;
          final capacity = [...zero];
          capacity[i] = houseUseCapacity(house, goal.typeId);
          if (capacity[i] == 0) continue;
          options[key(capacity)] = _Portfolio(
            cost,
            capacity,
            {house.id: goal.typeId},
            {house.id},
          );
        }
      }
      for (final child in children[house.id] ?? <LodgingHouse>[]) {
        options = merge(options, subtree(child));
      }
      options[zeroKey] = empty;
      return options;
    }

    var portfolio = <String, _Portfolio>{zeroKey: empty};
    if (active.isNotEmpty) {
      for (final root in children[null] ?? <LodgingHouse>[]) {
        portfolio = merge(portfolio, subtree(root));
      }
    }
    final result = portfolio[key(active.map((g) => g.amount).toList())];
    // Do not present an incomplete set of houses as a successful combined plan.
    final best = result ?? empty;
    return TownHouseInvestment(
      usages: Map.unmodifiable(best.usages),
      requiredHouseIds: Set.unmodifiable(best.required),
      addedCapacity: Map.unmodifiable({
        for (var i = 0; i < active.length; i++)
          active[i].typeId: best.capacity[i],
      }),
      cp: best.cp,
      isFeasible: result != null,
    );
  }
}

final class _Portfolio {
  const _Portfolio(this.cp, this.capacity, this.usages, this.required);
  final int cp;
  final List<int> capacity;
  final Map<String, int> usages;
  final Set<String> required;
}

bool _better(_Portfolio a, _Portfolio b) {
  if (a.cp != b.cp) return a.cp < b.cp;
  if (a.required.length != b.required.length) {
    return a.required.length < b.required.length;
  }
  final aCapacity = a.capacity.fold(0, (a, b) => a + b);
  final bCapacity = b.capacity.fold(0, (a, b) => a + b);
  if (aCapacity != bCapacity) return aCapacity < bCapacity;
  final aIds = a.usages.entries.map((e) => '${e.key}:${e.value}').toList()
    ..sort();
  final bIds = b.usages.entries.map((e) => '${e.key}:${e.value}').toList()
    ..sort();
  return aIds.join(',').compareTo(bIds.join(',')) < 0;
}
