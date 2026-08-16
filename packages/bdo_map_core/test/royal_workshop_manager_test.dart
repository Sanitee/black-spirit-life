import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses palace overview then one-worker area management flow', (
    tester,
  ) async {
    var plan = BdoRoyalWorkshopPlan(accessInvested: true);
    var housingOpened = false;
    const goods = <BdoRoyalWorkshopGood>[
      BdoRoyalWorkshopGood(
        id: 821120,
        name: 'Dew-kissed Green Plum',
        kind: BdoRoyalWorkshopKind.production,
        referencePrice: 35000,
        rareRoll: false,
      ),
      BdoRoyalWorkshopGood(
        id: 821136,
        name: 'Bountiful Feast',
        kind: BdoRoyalWorkshopKind.production,
        referencePrice: 1500000000,
        rareRoll: true,
        durationAt150WorkerSpeedHours: 29,
      ),
    ];

    await tester.binding.setSurfaceSize(const Size(1100, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: SizedBox(
                width: 980,
                height: 740,
                child: BdoRoyalWorkshopManager(
                  plan: plan,
                  goods: goods,
                  yukjoHiredWorkers: 3,
                  yukjoLodgingSlots: 7,
                  onChanged: (next) => setState(() => plan = next),
                  onOpenYukjoHousing: () => housingOpened = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('resource-map-royal-workshop-overview')),
      findsOneWidget,
    );
    expect(find.text('Gyeonghoeru Pavilion'), findsOneWidget);
    expect(find.text('Palace Kitchen'), findsOneWidget);
    expect(find.textContaining('3 hired'), findsOneWidget);
    expect(find.textContaining('7 slots'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('royal-workshop-open-yukjo-housing')),
    );
    expect(housingOpened, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('royal-workshop-area-button-infirmary')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('royal-workshop-area-infirmary')),
      findsOneWidget,
    );
    expect(find.text('YUKJO WORKER'), findsOneWidget);
    expect(find.text('CURRENT PRODUCTION ROLL'), findsOneWidget);
    expect(find.text('Basic workshop'), findsWidgets);
    expect(find.text('Item currently shown in BDO'), findsOneWidget);
    expect(find.textContaining('do not guess which workshop'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('Mark running'), findsOneWidget);
  });

  testWidgets('shows rare-roll warning and keeps it out of income', (
    tester,
  ) async {
    final plan = BdoRoyalWorkshopPlan(
      accessInvested: true,
      areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
        'infirmary': BdoRoyalWorkshopAreaPlan(
          workerName: 'Yukjo worker 1',
          isRunning: true,
          workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
            0: BdoRoyalWorkshopSlotPlan(
              selectedGoodId: 821136,
              recordedGoodName: 'Bountiful Feast',
              taskHours: 29,
              netSilverPerCycle: 1500000000,
              isRareOrSpecial: true,
            ),
          },
        ),
      },
    );
    const goods = <BdoRoyalWorkshopGood>[
      BdoRoyalWorkshopGood(
        id: 821136,
        name: 'Bountiful Feast',
        kind: BdoRoyalWorkshopKind.production,
        referencePrice: 1500000000,
        rareRoll: true,
        durationAt150WorkerSpeedHours: 29,
      ),
    ];

    await tester.binding.setSurfaceSize(const Size(1100, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 980,
              height: 740,
              child: BdoRoyalWorkshopManager(
                plan: plan,
                goods: goods,
                onChanged: (_) {},
                onOpenYukjoHousing: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Rare rolls stay visible'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('royal-workshop-income-summary')),
      findsNothing,
    );
  });

  testWidgets(
    'workshop switch persists only after confirm and cancel keeps active slot',
    (tester) async {
      var plan = BdoRoyalWorkshopPlan(
        accessInvested: true,
        areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
          'infirmary': BdoRoyalWorkshopAreaPlan(
            unlockedWorkshopCount: 2,
            workerName: 'Yukjo worker 1',
            workshopPlans: <int, BdoRoyalWorkshopSlotPlan>{
              0: BdoRoyalWorkshopSlotPlan(recordedGoodName: 'First roll'),
              1: BdoRoyalWorkshopSlotPlan(recordedGoodName: 'Second roll'),
            },
          ),
        },
      );

      await tester.binding.setSurfaceSize(const Size(1100, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Center(
                child: SizedBox(
                  width: 980,
                  height: 740,
                  child: BdoRoyalWorkshopManager(
                    plan: plan,
                    goods: const <BdoRoyalWorkshopGood>[],
                    yukjoHiredWorkers: 2,
                    onChanged: (next) => setState(() => plan = next),
                    onOpenYukjoHousing: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('royal-workshop-area-button-infirmary')),
      );
      await tester.pumpAndSettle();

      TextField currentTask() =>
          tester.widget<TextField>(find.byType(TextField).first);

      expect(currentTask().controller?.text, 'First roll');
      expect(find.text('Yukjo worker 1'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('royal-workshop-slot-infirmary-1')),
      );
      await tester.pumpAndSettle();

      expect(currentTask().controller?.text, 'Second roll');
      expect(plan.planFor('infirmary').normalizedActiveWorkshopIndex, 0);
      expect(find.text('Change active workshop?'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('royal-workshop-change-cancel')),
      );
      await tester.pumpAndSettle();

      expect(currentTask().controller?.text, 'First roll');
      expect(plan.planFor('infirmary').normalizedActiveWorkshopIndex, 0);

      await tester.tap(
        find.byKey(const ValueKey('royal-workshop-slot-infirmary-1')),
      );
      await tester.pumpAndSettle();
      expect(plan.planFor('infirmary').normalizedActiveWorkshopIndex, 0);

      await tester.tap(
        find.byKey(const ValueKey('royal-workshop-change-confirm')),
      );
      await tester.pumpAndSettle();

      expect(plan.planFor('infirmary').normalizedActiveWorkshopIndex, 1);
      expect(currentTask().controller?.text, 'Second roll');
      expect(
        plan.planFor('infirmary').planFor(0).recordedGoodName,
        'First roll',
      );
      expect(
        plan.planFor('infirmary').planFor(1).recordedGoodName,
        'Second roll',
      );
      expect(plan.planFor('infirmary').effectiveWorkerName, 'Yukjo worker 1');
    },
  );

  testWidgets('records a named workshop unlock without unlocking its prefix', (
    tester,
  ) async {
    var plan = BdoRoyalWorkshopPlan(
      accessInvested: true,
      areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
        'infirmary': BdoRoyalWorkshopAreaPlan(),
      },
    );

    await tester.binding.setSurfaceSize(const Size(1100, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: SizedBox(
                width: 980,
                height: 740,
                child: BdoRoyalWorkshopManager(
                  plan: plan,
                  goods: const <BdoRoyalWorkshopGood>[],
                  onChanged: (next) => setState(() => plan = next),
                  onOpenYukjoHousing: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('royal-workshop-area-button-infirmary')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bujeong'), findsOneWidget);
    expect(plan.planFor('infirmary').unlockedIndices, <int>{0});

    await tester.tap(
      find.byKey(const ValueKey('royal-workshop-slot-infirmary-3')),
    );
    await tester.pumpAndSettle();

    final area = plan.planFor('infirmary');
    expect(area.unlockedIndices, <int>{0, 3});
    expect(area.isWorkshopUnlocked(1), isFalse);
    expect(area.isWorkshopUnlocked(2), isFalse);
    expect(area.normalizedActiveWorkshopIndex, 0);
    expect(find.text('Change active workshop?'), findsOneWidget);
    expect(find.textContaining('Basic workshop'), findsWidgets);
    expect(find.textContaining('Bujeong'), findsWidgets);
  });

  testWidgets('assigning one worker and a task enables one running area', (
    tester,
  ) async {
    var plan = BdoRoyalWorkshopPlan(accessInvested: true);

    await tester.binding.setSurfaceSize(const Size(1100, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: SizedBox(
                width: 980,
                height: 740,
                child: BdoRoyalWorkshopManager(
                  plan: plan,
                  goods: const <BdoRoyalWorkshopGood>[],
                  yukjoHiredWorkers: 2,
                  onChanged: (next) => setState(() => plan = next),
                  onOpenYukjoHousing: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('royal-workshop-area-button-infirmary')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('royal-workshop-worker-infirmary')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yukjo worker 1').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Current herb roll');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('royal-workshop-start-infirmary')),
    );
    await tester.pumpAndSettle();

    expect(plan.assignedWorkerCount, 1);
    expect(plan.runningTaskCount, 1);
    expect(plan.planFor('infirmary').effectiveIsRunning, isTrue);
  });

  testWidgets(
    'worker and production selectors keep full names at narrow high text scale',
    (tester) async {
      const viewport = Size(720, 760);
      const workerName =
          'Yukjo worker assigned to the Moonlit Infirmary Pavilion';
      const goodName =
          'Moonlit Banquet Ingredient Selection for the Royal Infirmary';
      var plan = BdoRoyalWorkshopPlan(
        accessInvested: true,
        areaPlans: const <String, BdoRoyalWorkshopAreaPlan>{
          'infirmary': BdoRoyalWorkshopAreaPlan(workerName: workerName),
        },
      );

      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: viewport,
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => Center(
                  child: SizedBox(
                    width: 660,
                    height: 700,
                    child: BdoRoyalWorkshopManager(
                      plan: plan,
                      goods: const <BdoRoyalWorkshopGood>[
                        BdoRoyalWorkshopGood(
                          id: 990001,
                          name: goodName,
                          kind: BdoRoyalWorkshopKind.production,
                          referencePrice: 100000,
                          rareRoll: false,
                        ),
                      ],
                      yukjoHiredWorkers: 1,
                      onChanged: (next) => setState(() => plan = next),
                      onOpenYukjoHousing: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final scaledInfirmaryButton = find.byKey(
        const ValueKey('royal-workshop-area-button-infirmary'),
      );
      await tester.ensureVisible(scaledInfirmaryButton);
      await tester.pumpAndSettle();
      await tester.tap(scaledInfirmaryButton);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('resource-map-royal-workshop-overview')),
        findsNothing,
      );

      final workerSelector = find.byKey(
        const ValueKey('royal-workshop-worker-infirmary'),
      );
      await tester.scrollUntilVisible(
        workerSelector,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final workerTexts = tester.widgetList<Text>(
        find.text(workerName, skipOffstage: false),
      );
      expect(workerTexts, isNotEmpty);
      expect(
        workerTexts.every(
          (text) =>
              text.overflow != TextOverflow.ellipsis && text.maxLines == null,
        ),
        isTrue,
      );
      final workerDropdown = tester.widget<DropdownButton<String>>(
        workerSelector,
      );
      expect(workerDropdown.menuWidth, isNotNull);
      expect(
        workerDropdown.menuWidth!,
        greaterThanOrEqualTo(tester.getSize(workerSelector).width),
      );
      expect(workerDropdown.menuWidth!, lessThanOrEqualTo(viewport.width - 24));

      await tester.tap(workerSelector);
      await tester.pumpAndSettle();
      expect(find.text(workerName), findsWidgets);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      final goodField = find.byType(TextField).first;
      await tester.enterText(goodField, 'Moonlit Banquet');
      await tester.pumpAndSettle();
      final optionSurface = find.byKey(
        const ValueKey<String>('royal-workshop-good-options'),
      );
      expect(optionSurface, findsOneWidget);
      expect(
        tester.getSize(optionSurface).width,
        lessThanOrEqualTo(viewport.width - 24),
      );
      final goodOption = find.text(goodName);
      expect(goodOption, findsOneWidget);
      final goodOptionText = tester.widget<Text>(goodOption);
      expect(goodOptionText.maxLines, isNull);
      expect(goodOptionText.overflow, TextOverflow.visible);
      final optionRect = tester.getRect(goodOption);
      expect(optionRect.left, greaterThanOrEqualTo(0));
      expect(optionRect.right, lessThanOrEqualTo(viewport.width));
      expect(optionRect.top, greaterThanOrEqualTo(0));
      expect(optionRect.bottom, lessThanOrEqualTo(viewport.height));
      expect(tester.takeException(), isNull);
    },
  );
}
