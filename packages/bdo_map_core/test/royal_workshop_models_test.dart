import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defines the familiar eight-area Seoul palace layout', () {
    expect(bdoRoyalWorkshopAreas, hasLength(8));
    expect(
      bdoRoyalWorkshopAreas.where(
        (area) => area.kind == BdoRoyalWorkshopKind.production,
      ),
      hasLength(4),
    );
    expect(
      bdoRoyalWorkshopAreas.where(
        (area) => area.kind == BdoRoyalWorkshopKind.processing,
      ),
      hasLength(4),
    );
    expect(bdoRoyalWorkshopAreasById['gyeonghoeru']?.managerName, 'Yeongman');
    expect(bdoRoyalWorkshopAreasById['infirmary']?.maximumWorkshops, 5);
    expect(bdoRoyalWorkshopAreasById['palace-kitchen']?.maximumWorkshops, 3);
    expect(
      bdoRoyalWorkshopAreasById['gyeonghoeru']?.workshopAt(1).name,
      'Hamhong Gate',
    );
    expect(
      bdoRoyalWorkshopAreasById['gyeonghoeru']?.workshopAt(0).name,
      'Basic workshop',
    );
    expect(
      bdoRoyalWorkshopAreas.every(
        (area) => area.workshopAt(0).name == 'Basic workshop',
      ),
      isTrue,
    );
    expect(
      bdoRoyalWorkshopAreasById['gyeonghoeru']
          ?.workshopAt(1)
          .morningGratitudeTokenCost,
      500,
    );
    expect(
      bdoRoyalWorkshopAreasById['gyeonghoeru']?.workshopAt(2).name,
      'Igyeon Gate',
    );
    expect(bdoRoyalWorkshopAreasById['gyeonghoeru']?.managerNpcId, 62114);
    expect(bdoRoyalWorkshopAreasById['gyeonghoeru']?.managerWorldX, -1399270);
  });

  test('round-trips one area worker with independent workshop tasks', () {
    final plan = BdoRoyalWorkshopPlan(
      accessInvested: true,
      freeRefreshAvailable: false,
      areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
        'infirmary': BdoRoyalWorkshopAreaPlan(
          unlockedWorkshopCount: 4,
          activeWorkshopIndex: 2,
          workerName: 'Yukjo worker 1',
          isRunning: true,
          workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
            0: BdoRoyalWorkshopSlotPlan(
              recordedGoodName: 'Dew-kissed Green Plum',
              taskHours: 3.5,
              repeatCount: 12,
              netSilverPerCycle: 420000,
            ),
            2: BdoRoyalWorkshopSlotPlan(
              recordedGoodName: 'Medicinal Herbs',
              taskHours: 7,
              repeatCount: 4,
              netSilverPerCycle: 900000,
            ),
          },
        ),
      },
    );

    final restored = BdoRoyalWorkshopPlan.fromJson(plan.toJson());

    expect(restored.sameValuesAs(plan), isTrue);
    expect(restored.accessInvested, isTrue);
    expect(restored.freeRefreshAvailable, isFalse);
    expect(restored.assignedWorkerCount, 1);
    expect(restored.runningTaskCount, 1);
    expect(
      restored.planFor('infirmary').planFor(0).recordedGoodName,
      'Dew-kissed Green Plum',
    );
    expect(restored.planFor('infirmary').effectiveWorkerName, 'Yukjo worker 1');
  });

  test(
    'only one active task per area is counted and rare rolls are excluded',
    () {
      const rare = BdoRoyalWorkshopGood(
        id: 2,
        name: 'Rare meal',
        kind: BdoRoyalWorkshopKind.production,
        referencePrice: 0,
        rareRoll: true,
        durationAt150WorkerSpeedHours: 29,
      );
      final result = estimateRoyalWorkshopIncome(
        plan: BdoRoyalWorkshopPlan(
          accessInvested: true,
          areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
            'infirmary': BdoRoyalWorkshopAreaPlan(
              unlockedWorkshopCount: 3,
              activeWorkshopIndex: 1,
              workerName: 'Yukjo worker 1',
              isRunning: true,
              workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
                0: BdoRoyalWorkshopSlotPlan(
                  recordedGoodName: 'Ordinary material',
                  taskHours: 2,
                  netSilverPerCycle: 1000000,
                ),
                1: BdoRoyalWorkshopSlotPlan(
                  recordedGoodName: 'Another material',
                  taskHours: 4,
                  repeatCount: 3,
                  netSilverPerCycle: 2000000,
                ),
              },
            ),
            'gyeonghoeru': BdoRoyalWorkshopAreaPlan(
              workerName: 'Yukjo worker 2',
              isRunning: true,
              workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
                0: BdoRoyalWorkshopSlotPlan(
                  selectedGoodId: 2,
                  recordedGoodName: 'Rare meal',
                  taskHours: 29,
                  isRareOrSpecial: true,
                ),
              },
            ),
          },
        ),
        goodsById: const <int, BdoRoyalWorkshopGood>{2: rare},
      );

      expect(result.netSilverPerOnlineHour, 1500000);
      expect(result.includedAreaCount, 1);
      expect(result.excludedRareAreaCount, 1);
    },
  );

  test('Royal access reserves its exact five contribution points', () {
    expect(BdoRoyalWorkshopPlan().reservedContributionPoints, 0);
    expect(
      BdoRoyalWorkshopPlan(accessInvested: true).reservedContributionPoints,
      bdoRoyalWorkshopAccessContributionPoints,
    );
    expect(bdoRoyalWorkshopAccessContributionPoints, 5);
  });

  test('a malformed running task without a worker is not counted', () {
    final result = estimateRoyalWorkshopIncome(
      plan: BdoRoyalWorkshopPlan(
        accessInvested: true,
        areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
          'infirmary': BdoRoyalWorkshopAreaPlan(
            workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
              0: BdoRoyalWorkshopSlotPlan(
                recordedGoodName: 'Ordinary material',
                taskHours: 2,
                netSilverPerCycle: 1000000,
                isRunning: true,
              ),
            },
          ),
        },
      ),
      goodsById: const <int, BdoRoyalWorkshopGood>{},
    );

    expect(result.netSilverPerOnlineHour, 0);
    expect(result.includedAreaCount, 0);
    expect(result.incompleteAreaCount, 1);
  });

  test('schema 7 single-area data migrates without losing the task', () {
    final migrated = BdoRoyalWorkshopAreaPlan.fromJson(<String, Object?>{
      'unlockedWorkshopCount': 3,
      'activeWorkshopIndex': 2,
      'selectedGoodId': 821121,
      'workerName': 'Worker A',
      'taskHours': 5.5,
      'repeatCount': 7,
      'netSilverPerCycle': 1230000,
      'isRunning': true,
    });

    final slot = migrated.planFor(2);
    expect(migrated.normalizedActiveWorkshopIndex, 2);
    expect(migrated.activePlan, same(slot));
    expect(slot.selectedGoodId, 821121);
    expect(migrated.effectiveWorkerName, 'Worker A');
    expect(slot.taskHours, 5.5);
    expect(slot.repeatCount, 7);
    expect(slot.netSilverPerCycle, 1230000);
    expect(migrated.effectiveIsRunning, isTrue);
  });

  test('named non-prefix workshop unlocks serialize and round-trip', () {
    final plan = BdoRoyalWorkshopPlan(
      accessInvested: true,
      areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
        'gyeonghoeru': BdoRoyalWorkshopAreaPlan(
          unlockedWorkshopIndices: <int>{0, 3, 4},
          activeWorkshopIndex: 3,
          workerName: 'Yukjo worker 1',
          workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
            3: BdoRoyalWorkshopSlotPlan(recordedGoodName: 'Hahyangjeong roll'),
          },
        ),
      },
    );

    final json = plan.toJson();
    final areaJson =
        (json['areaPlans']! as Map<String, Object?>)['gyeonghoeru']!
            as Map<String, Object?>;
    final restored = BdoRoyalWorkshopPlan.fromJson(json);
    final restoredArea = restored.planFor('gyeonghoeru');

    expect(areaJson['unlockedWorkshopIndices'], <int>[0, 3, 4]);
    expect(restoredArea.unlockedIndices, <int>{0, 3, 4});
    expect(restoredArea.unlockedWorkshopCount, 3);
    expect(restoredArea.normalizedActiveWorkshopIndex, 3);
    expect(restoredArea.isWorkshopUnlocked(1), isFalse);
    expect(restoredArea.isWorkshopUnlocked(2), isFalse);
    expect(restoredArea.planFor(3).recordedGoodName, 'Hahyangjeong roll');
    expect(restored.sameValuesAs(plan), isTrue);
  });

  test('plan load clamps malformed unlock and active data to area limits', () {
    final restored = BdoRoyalWorkshopPlan.fromJson(<String, Object?>{
      'accessInvested': true,
      'areaPlans': <String, Object?>{
        'palace-kitchen': <String, Object?>{
          'unlockedWorkshopCount': 99,
          'activeWorkshopIndex': 98,
          'workshopPlans': <String, Object?>{
            '2': <String, Object?>{'recordedGoodName': 'Valid processing task'},
            '98': <String, Object?>{'recordedGoodName': 'Out-of-range task'},
          },
        },
      },
    });
    final area = restored.planFor('palace-kitchen');

    expect(
      area.unlockedWorkshopCount,
      bdoRoyalWorkshopAreasById['palace-kitchen']!.maximumWorkshops,
    );
    expect(area.unlockedIndices, <int>{0, 1, 2});
    expect(area.normalizedActiveWorkshopIndex, 0);
    expect(area.planFor(2).recordedGoodName, 'Valid processing task');
    expect(area.workshopPlans, isNot(contains(98)));
  });

  test('incorrect per-slot runtime data migrates to one current area task', () {
    final migrated = BdoRoyalWorkshopAreaPlan.fromJson(<String, Object?>{
      'unlockedWorkshopCount': 3,
      'activeWorkshopIndex': 0,
      'workshopPlans': <String, Object?>{
        '0': <String, Object?>{
          'recordedGoodName': 'Old first task',
          'workerName': 'Worker A',
          'isRunning': true,
        },
        '2': <String, Object?>{
          'recordedGoodName': 'Old second task',
          'workerName': 'Worker B',
          'isRunning': true,
        },
      },
    });

    expect(migrated.activeWorkshopIndex, 0);
    expect(migrated.effectiveWorkerName, 'Worker A');
    expect(migrated.effectiveIsRunning, isTrue);
    expect(migrated.planFor(0).workerName, isEmpty);
    expect(migrated.planFor(2).isRunning, isFalse);
  });

  test('duplicate Yukjo workers are reported across palace areas', () {
    final plan = BdoRoyalWorkshopPlan(
      areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
        'infirmary': BdoRoyalWorkshopAreaPlan(workerName: 'Yukjo worker 1'),
        'military': BdoRoyalWorkshopAreaPlan(workerName: 'yukjo worker 1'),
      },
    );

    expect(plan.assignedWorkerCount, 2);
    expect(plan.duplicateWorkerNames, <String>{'Yukjo worker 1'});
    expect(plan.hasDuplicateWorkerName('YUKJO WORKER 1'), isTrue);
  });

  test('duplicate workers never inflate the Royal income estimate', () {
    const task = BdoRoyalWorkshopSlotPlan(
      recordedGoodName: 'Ordinary material',
      taskHours: 2,
      netSilverPerCycle: 1000000,
    );
    final result = estimateRoyalWorkshopIncome(
      plan: BdoRoyalWorkshopPlan(
        accessInvested: true,
        areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
          'infirmary': BdoRoyalWorkshopAreaPlan(
            workerName: 'Yukjo worker 1',
            isRunning: true,
            workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{0: task},
          ),
          'gyeonghoeru': BdoRoyalWorkshopAreaPlan(
            workerName: 'YUKJO WORKER 1',
            isRunning: true,
            workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{0: task},
          ),
        },
      ),
      goodsById: const <int, BdoRoyalWorkshopGood>{},
    );

    expect(result.netSilverPerOnlineHour, 0);
    expect(result.includedAreaCount, 0);
    expect(result.incompleteAreaCount, 2);
  });

  test('current node preferences schema persists the distinct Royal setup', () {
    final preferences = BdoNodeNetworkPreferences(
      royalWorkshopPlan: BdoRoyalWorkshopPlan(
        accessInvested: true,
        areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
          'leftward-office': BdoRoyalWorkshopAreaPlan(
            workerName: 'Yukjo worker 1',
            workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
              0: BdoRoyalWorkshopSlotPlan(
                selectedGoodId: 821121,
                recordedGoodName: 'Workshop roll',
              ),
            },
          ),
        },
      ),
    );

    final json = preferences.toJson();
    final restored = BdoNodeNetworkPreferences.fromJson(json);

    expect(json['schemaVersion'], BdoNodeNetworkPreferences.schemaVersion);
    expect(restored.sameValuesAs(preferences), isTrue);
    expect(restored.royalWorkshopPlan.accessInvested, isTrue);
    expect(
      restored.royalWorkshopPlan
          .planFor('leftward-office')
          .planFor(0)
          .selectedGoodId,
      821121,
    );
  });
}
