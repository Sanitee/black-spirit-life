import 'dart:io';

import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BairogCalculator calculator;
  setUpAll(() {
    calculator = BairogCalculator(
      BairogCalculatorData.fromJsonString(
        File('assets/data/bairog_calculator.json').readAsStringSync(),
      ),
    );
  });

  BairogRouteProjection project({
    Set<int> expenses = const {},
    int gathers = 1000,
    double startingEnergy = 500,
    double natural = 0,
  }) => calculator.projectRoute(
    routeId: 17,
    settings: BairogCalculatorSettings(
      minigameMode: BairogMinigameMode.none,
      enabledExpenseItemIds: expenses,
      customGathersPerHour: {17: gathers},
      yourEnergy: startingEnergy,
      naturalEnergyRecoveryPerThreeMinutes: natural,
    ),
    marketPricesByBdoItemId: const {
      589: 10,
      820150: 100,
      821144: 300,
      821145: 150,
    },
  );

  test('herbal rates match 20 three-minute ticks, not upstream typo', () {
    expect(project(expenses: {821145}).energy.selectedRecoveryPerHour, 500);
    expect(project(expenses: {821144}).energy.selectedRecoveryPerHour, 1000);
    expect(project(expenses: {820150}).energy.selectedRecoveryPerHour, 600);
  });

  test('XL rate and cost both use six 50-energy doses per hour', () {
    final energy = project(expenses: {589}).energy;
    expect(energy.selectedRecoveryPerHour, 6 * 50);
    expect(energy.hourlyExpenseSilver, 6 * 10);
    expect(energy.sessionHours, closeTo(500 / (700 - 300), 1e-10));
  });

  test(
    'Mellow can renew at its three-hour cooldown; session cost rounds up',
    () {
      final energy = project(expenses: {821145}, startingEnergy: 1000).energy;
      expect(energy.sessionHours, 5);
      expect(energy.hourlyExpenseSilver, 50);
      expect(energy.energyDumpExpenseSilver, 300);
      expect(energy.netEnergyDrainAfterTemporaryRecovery, isNull);
    },
  );

  test(
    'Miraculous runs out after one hour, even when initially sustainable',
    () {
      final energy = project(expenses: {820150}, gathers: 500).energy;
      expect(energy.netEnergyDrainPerHour, -250);
      expect(energy.netEnergyDrainAfterTemporaryRecovery, 350);
      expect(energy.temporaryRecoveryHours, 1);
      expect(energy.sessionHours, closeTo(1 + 1250 / 350, 1e-10));
      expect(energy.sessionHours.isFinite, isTrue);
      expect(energy.energyDumpExpenseSilver, 100);
    },
  );

  test('Miraculous expiry also applies when initial drain is positive', () {
    final energy = project(expenses: {820150}).energy;
    expect(energy.netEnergyDrainPerHour, 100);
    expect(energy.sessionHours, closeTo(1 + 900 / 700, 1e-10));
    expect(energy.energyDumpExpenseSilver, 100);
  });

  test(
    'a session ending before Miraculous expiry uses only elapsed recovery',
    () {
      final energy = project(expenses: {820150}, gathers: 3000).energy;
      expect(energy.sessionHours, closeTo(1000 / 1500, 1e-10));
      expect(energy.energyDumpExpenseSilver, 100);
    },
  );

  test('exact one-hour depletion does not add another hour or dose', () {
    final energy = project(
      expenses: {820150},
      gathers: 3000,
      startingEnergy: 1000,
    ).energy;
    expect(energy.sessionHours, 1);
    expect(energy.energyDumpExpenseSilver, 100);
  });

  test(
    'a long session still plans one dose, never hourly Miraculous reuse',
    () {
      final energy = project(expenses: {820150}, gathers: 50).energy;
      expect(energy.sessionHours, closeTo(1 + 1565 / 35, 1e-10));
      expect(energy.sessionHours, greaterThan(22));
      expect(energy.energyDumpExpenseSilver, 100);
    },
  );

  test('sustainability is allowed only if remaining recovery covers drain', () {
    final energy = project(expenses: {820150, 589}, gathers: 400).energy;
    expect(energy.netEnergyDrainAfterTemporaryRecovery, -20);
    expect(energy.sessionHours, double.infinity);
  });

  test('direct caller cannot stack mutually exclusive Royal medicines', () {
    final both = project(expenses: {821144, 821145}).energy;
    final mystical = project(expenses: {821144}).energy;
    expect(both.selectedRecoveryPerHour, mystical.selectedRecoveryPerHour);
    expect(both.hourlyExpenseSilver, mystical.hourlyExpenseSilver);
    expect(both.sessionHours, mystical.sessionHours);
  });

  test(
    'legacy invalid pair retains choices without adding impossible rates',
    () {
      final restored = BairogCalculatorSettings.fromJson({
        'expensesEnabled': {'821144': true, '821145': true},
      });
      expect(restored.enabledExpenseItemIds, {821144, 821145});
      expect(restored.activeEnergyExpenses.map((e) => e.bdoItemId), [821144]);
    },
  );

  test('zero energy without refills has zero session and zero expense', () {
    final energy = project(startingEnergy: 0).energy;
    expect(energy.sessionHours, 0);
    expect(energy.energyDumpExpenseSilver, 0);
  });
}
