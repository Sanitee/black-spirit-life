import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BdoRoyalWorkshopPlan _plan(BdoRoyalWorkshopSlotPlan slot) =>
    BdoRoyalWorkshopPlan(
      accessInvested: true,
      areaPlans: <String, BdoRoyalWorkshopAreaPlan>{
        'infirmary': BdoRoyalWorkshopAreaPlan(
          workerName: 'Synthetic Yukjo worker',
          isRunning: true,
          workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{0: slot},
        ),
      },
    );

void main() {
  const slot = BdoRoyalWorkshopSlotPlan(
    recordedGoodName: 'Synthetic ordinary recipe',
    taskHours: 2,
    repeatCount: 4,
    netSilverPerCycle: -500000,
  );
  test('loss is preserved in saved plan, preview and aggregate', () {
    final restored = BdoRoyalWorkshopPlan.fromJson(_plan(slot).toJson());
    expect(restored.planFor('infirmary').activePlan.netSilverPerCycle, -500000);
    expect(
      restored.planFor('infirmary').activePlan.netSilverPerOnlineHour,
      -1000000,
    );
    final estimate = estimateRoyalWorkshopIncome(
      plan: restored,
      goodsById: const {},
    );
    expect(estimate.netSilverPerOnlineHour, -1000000);
    expect(estimate.includedAreaCount, 1);
  });
  test('legacy per-area loss survives conversion to a slot', () {
    final restored = BdoRoyalWorkshopAreaPlan.fromJson({
      'recordedGoodName': 'Synthetic ordinary recipe',
      'taskHours': 2,
      'netSilverPerCycle': -500000,
      'workerName': 'Synthetic Yukjo worker',
    });
    expect(restored.activePlan.netSilverPerCycle, -500000);
  });
  test('zero value is known; missing value is incomplete', () {
    expect(slot.copyWith(netSilverPerCycle: 0).netSilverPerOnlineHour, 0);
    expect(
      slot.copyWith(clearNetSilverPerCycle: true).netSilverPerOnlineHour,
      isNull,
    );
  });
  for (final invalid in <BdoRoyalWorkshopSlotPlan>[
    slot.copyWith(taskHours: 0),
    slot.copyWith(taskHours: -2),
    slot.copyWith(taskHours: double.infinity),
    slot.copyWith(taskHours: double.nan),
    slot.copyWith(netSilverPerCycle: double.infinity),
    slot.copyWith(netSilverPerCycle: double.nan),
    slot.copyWith(repeatCount: 0),
    slot.copyWith(repeatCount: -1),
    slot.copyWith(netSilverPerCycle: 1e308),
  ].indexed) {
    test('invalid numeric case ${invalid.$1} remains incomplete', () {
      expect(invalid.$2.netSilverPerOnlineHour, isNull);
      final estimate = estimateRoyalWorkshopIncome(
        plan: _plan(invalid.$2),
        goodsById: const {},
      );
      expect(estimate.netSilverPerOnlineHour, 0);
      expect(estimate.includedAreaCount, 0);
      expect(estimate.incompleteAreaCount, 1);
    });
  }
  testWidgets('net input retains minus; unfinished inputs clear estimates', (
    tester,
  ) async {
    var plan = _plan(slot);
    await tester.binding.setSurfaceSize(const Size(1100, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => BdoRoyalWorkshopManager(
              plan: plan,
              goods: const [],
              onChanged: (next) => setState(() => plan = next),
              onOpenYukjoHousing: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('royal-workshop-area-button-infirmary')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Income'));
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    final net = find.byKey(const ValueKey('royal-workshop-net-infirmary-0'));
    final hours = find.byKey(
      const ValueKey('royal-workshop-hours-infirmary-0'),
    );
    await tester.ensureVisible(net);
    await tester.enterText(net, '-1.5');
    await tester.pump();
    expect(plan.planFor('infirmary').activePlan.netSilverPerCycle, -1500000);
    await tester.enterText(net, '-');
    await tester.pump();
    expect(plan.planFor('infirmary').activePlan.netSilverPerCycle, isNull);
    await tester.enterText(net, '0');
    await tester.pump();
    expect(plan.planFor('infirmary').activePlan.netSilverPerCycle, 0);
    await tester.enterText(hours, '.');
    await tester.pump();
    expect(plan.planFor('infirmary').activePlan.taskHours, isNull);
    expect(tester.takeException(), isNull);
  });
}
