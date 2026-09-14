import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bdo_map_core/src/lodging/lodging_data.dart';
import 'package:bdo_map_core/src/lodging/town_house_investment.dart';

void main() {
  final data = LodgingDataset.fromJsonString(
    File('assets/data/lodging_houses.json').readAsStringSync(),
  );
  final altinova = data.townsByNodeId['1101']!;

  test(
    'approved Altinova examples share chains and assign one use per house',
    () {
      final cases = <List<TownHouseGoal>, int>{
        [const TownHouseGoal(2, 16)]: 3,
        [const TownHouseGoal(2, 16), const TownHouseGoal(3, 1)]: 6,
        [
          const TownHouseGoal(2, 16),
          const TownHouseGoal(3, 1),
          const TownHouseGoal(1403, 1),
        ]: 7,
      };
      for (final entry in cases.entries) {
        final plan = TownHouseInvestmentPlanner.solve(
          town: altinova,
          goals: entry.key,
        );
        expect(plan.isFeasible, isTrue);
        expect(plan.cp, entry.value);
        _validate(altinova, plan, entry.key, {});
      }
    },
  );
  test(
    'multiple different workshops coexist and owned usages stay protected',
    () {
      const goals = [
        TownHouseGoal(2, 16),
        TownHouseGoal(1403, 1),
        TownHouseGoal(16, 1),
      ];
      final owned = {'house:2866', 'house:2910'};
      final plan = TownHouseInvestmentPlanner.solve(
        town: altinova,
        goals: goals,
        owned: owned,
      );
      expect(plan.isFeasible, isTrue);
      expect(plan.usages.keys.toSet().intersection(owned), isEmpty);
      _validate(altinova, plan, goals, owned);
    },
  );
  test('zero targets produce no unnecessary houses', () {
    final plan = TownHouseInvestmentPlanner.solve(
      town: altinova,
      goals: const [TownHouseGoal(2, 0)],
    );
    expect(plan.requiredHouseIds, isEmpty);
    expect(plan.cp, 0);
    expect(plan.isFeasible, isTrue);
  });
  test(
    'impossible combined goals are not presented as a successful partial plan',
    () {
      final plan = TownHouseInvestmentPlanner.solve(
        town: altinova,
        goals: const [TownHouseGoal(3, 999)],
      );
      expect(plan.isFeasible, isFalse);
      expect(plan.requiredHouseIds, isEmpty);
    },
  );
  test('Calpheon combined planning uses full street, room and floor names', () {
    final town = data.towns.firstWhere((t) => t.name == 'Calpheon City');
    expect(
      town.houses.any((h) => h.name == 'Workshop District 1-1, Rm. 2'),
      isTrue,
    );
    expect(
      town.houses.any((h) => h.name == 'Workshop District 2-5, 2F'),
      isTrue,
    );
    const goals = [
      TownHouseGoal(1, 3),
      TownHouseGoal(2, 16),
      TownHouseGoal(3, 1),
      TownHouseGoal(14, 1),
      TownHouseGoal(16, 1),
    ];
    final timer = Stopwatch()..start();
    final plan = TownHouseInvestmentPlanner.solve(town: town, goals: goals);
    expect(plan.isFeasible, isTrue);
    _validate(town, plan, goals, {});
    expect(timer.elapsed.inSeconds, lessThan(15));
  });
  test('minimum workshop levels and duplicate type validation', () {
    const goal = TownHouseGoal(1403, 1, minimumLevel: 2);
    final plan = TownHouseInvestmentPlanner.solve(
      town: altinova,
      goals: const [goal],
    );
    _validate(altinova, plan, [goal], {});
    expect(
      () => TownHouseInvestmentPlanner.solve(
        town: altinova,
        goals: const [TownHouseGoal(2, 1), TownHouseGoal(2, 1)],
      ),
      throwsArgumentError,
    );
  });
}

void _validate(
  LodgingTown town,
  TownHouseInvestment plan,
  List<TownHouseGoal> goals,
  Set<String> owned,
) {
  var cp = 0;
  for (final id in plan.requiredHouseIds) {
    final house = town.housesById[id]!;
    if (!owned.contains(id)) cp += house.contributionPoints;
    if (house.prerequisiteHouseId != null) {
      expect(plan.requiredHouseIds.contains(house.prerequisiteHouseId), isTrue);
    }
  }
  expect(plan.cp, cp);
  for (final goal in goals) {
    var actual = 0;
    for (final entry in plan.usages.entries.where(
      (e) => e.value == goal.typeId,
    )) {
      final house = town.housesById[entry.key]!;
      expect(owned.contains(house.id), isFalse);
      expect(
        house.usagesByTypeId[goal.typeId]!.level,
        greaterThanOrEqualTo(goal.minimumLevel),
      );
      actual += houseUseCapacity(house, goal.typeId);
    }
    expect(actual, greaterThanOrEqualTo(goal.amount));
    expect(plan.addedCapacity[goal.typeId], actual);
  }
}
