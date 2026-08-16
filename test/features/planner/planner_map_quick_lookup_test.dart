import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  testWidgets(
    'Need First right-click queues worker materials without opening the map',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(
        resolveMapLookup: (materialName) async => PlannerMapLookupAvailability(
          materialName: materialName,
          hasManualGathering: true,
          manualResourceId: 'sunrise-herb',
          manualLocationCount: 1,
          hasWorkerNodes: true,
          workerResourceId: 'sunrise-herb',
        ),
      );
      addTearDown(harness.controller.dispose);
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump();

      final region = find.byKey(
        PlannerActionKeys.mapLookupRegion('need:Sunrise Herb'),
      );
      expect(region, findsOneWidget);

      await tester.tap(
        region,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(find.text('Show gathering locations'), findsOneWidget);
      expect(find.text('Add to planned network'), findsOneWidget);
      expect(harness.copied, isEmpty);

      await tester.tap(
        find.byKey(
          PlannerActionKeys.mapLookupAction(
            'need:Sunrise Herb',
            'addToPlannedNetwork',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(harness.plannedNetworkAdds, hasLength(1));
      expect(harness.plannedNetworkAdds.single.materialName, 'Sunrise Herb');
      expect(
        harness.plannedNetworkAdds.single.workerResourceId,
        'sunrise-herb',
      );
      expect(harness.mapLookupRequests, isEmpty);

      await tester.tap(
        find.byKey(PlannerActionKeys.row('P20', 'Sunrise Herb')),
      );
      await tester.pump();
      expect(harness.copied, <String>['Sunrise Herb']);
    },
  );

  testWidgets('manual gathering action opens the exact resolved resource', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(
      resolveMapLookup: (materialName) async => PlannerMapLookupAvailability(
        materialName: materialName,
        hasManualGathering: true,
        manualResourceId: 'item:5400',
        manualLocationCount: 1,
        hasWorkerNodes: true,
        workerResourceId: 'item:5400',
      ),
    );
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump();

    await tester.tap(
      find.byKey(PlannerActionKeys.mapLookupRegion('need:Sunrise Herb')),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        PlannerActionKeys.mapLookupAction(
          'need:Sunrise Herb',
          PlannerMapLookupSource.manualGathering.name,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.mapLookupRequests, hasLength(1));
    expect(
      harness.mapLookupRequests.single,
      isA<PlannerMapLookupRequest>()
          .having(
            (request) => request.materialName,
            'materialName',
            'Sunrise Herb',
          )
          .having((request) => request.resourceId, 'resourceId', 'item:5400')
          .having(
            (request) => request.source,
            'source',
            PlannerMapLookupSource.manualGathering,
          ),
    );
  });

  testWidgets('NPC vendor action opens every mapped seller for the material', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(
      resolveMapLookup: (materialName) async => PlannerMapLookupAvailability(
        materialName: materialName,
        hasNpcVendors: true,
        npcVendorCount: 46,
      ),
    );
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump();

    await tester.tap(
      find.byKey(PlannerActionKeys.mapLookupRegion('need:Sunrise Herb')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    final vendorAction = find.byKey(
      PlannerActionKeys.mapLookupAction(
        'need:Sunrise Herb',
        PlannerMapLookupSource.npcVendors.name,
      ),
    );
    expect(vendorAction, findsOneWidget);
    expect(find.text('Show NPC vendors'), findsOneWidget);
    expect(find.text('46 mapped vendor locations'), findsOneWidget);
    expect(
      find.descendant(
        of: vendorAction,
        matching: find.byIcon(Icons.storefront_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('Show gathering locations'), findsNothing);
    expect(find.text('Add to checklist'), findsNothing);
    expect(find.text('Add to planned network'), findsNothing);

    await tester.tap(vendorAction);
    await tester.pumpAndSettle();

    expect(harness.mapLookupRequests, hasLength(1));
    expect(
      harness.mapLookupRequests.single,
      isA<PlannerMapLookupRequest>()
          .having(
            (request) => request.materialName,
            'materialName',
            'Sunrise Herb',
          )
          .having((request) => request.resourceId, 'resourceId', isNull)
          .having(
            (request) => request.source,
            'source',
            PlannerMapLookupSource.npcVendors,
          ),
    );
  });

  testWidgets(
    'gather-checklist action forwards the exact resolved item without opening the map',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final added = <PlannerMapLookupAvailability>[];
      final availability = PlannerMapLookupAvailability(
        materialName: 'Sunrise Herb',
        hasManualGathering: true,
        manualResourceId: 'item:5400',
        manualLocationCount: 1,
        hasWorkerNodes: true,
        workerResourceId: 'item:5400',
      );
      final harness = PlannerTestHarness(
        resolveMapLookup: (_) async => availability,
        addToGatherChecklist: added.add,
      );
      addTearDown(harness.controller.dispose);
      await tester.pumpWidget(harness.plannerHost());
      await tester.pump();

      await tester.tap(
        find.byKey(PlannerActionKeys.mapLookupRegion('need:Sunrise Herb')),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(find.text('Show gathering locations'), findsOneWidget);
      expect(find.text('Add to planned network'), findsOneWidget);
      expect(find.text('Add to checklist'), findsOneWidget);
      final manualAction = find.byKey(
        PlannerActionKeys.mapLookupAction(
          'need:Sunrise Herb',
          PlannerMapLookupSource.manualGathering.name,
        ),
      );
      final checklistAction = find.byKey(
        PlannerActionKeys.mapLookupAction(
          'need:Sunrise Herb',
          'addToGatherChecklist',
        ),
      );
      final networkAction = find.byKey(
        PlannerActionKeys.mapLookupAction(
          'need:Sunrise Herb',
          'addToPlannedNetwork',
        ),
      );
      for (final iconCase in <(Finder, IconData)>[
        (manualAction, Icons.location_on_rounded),
        (checklistAction, Icons.checklist_rounded),
        (networkAction, Icons.account_tree_rounded),
      ]) {
        final icon = tester.widget<Icon>(
          find.descendant(of: iconCase.$1, matching: find.byIcon(iconCase.$2)),
        );
        expect(icon.size, 23);
      }
      expect(find.byType(PopupMenuDivider), findsOneWidget);

      await tester.tap(
        find.byKey(
          PlannerActionKeys.mapLookupAction(
            'need:Sunrise Herb',
            'addToGatherChecklist',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(added, hasLength(1));
      expect(added.single, same(availability));
      expect(added.single.manualResourceId, 'item:5400');
      expect(added.single.workerResourceId, 'item:5400');
      expect(harness.mapLookupRequests, isEmpty);
    },
  );

  testWidgets('manual-only materials never advertise worker nodes', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(
      resolveMapLookup: (materialName) async => PlannerMapLookupAvailability(
        materialName: materialName,
        hasManualGathering: true,
        manualResourceId: 'sunrise-herb',
        manualLocationCount: 1,
      ),
    );
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump();

    await tester.tap(
      find.byKey(PlannerActionKeys.mapLookupRegion('need:Sunrise Herb')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text('Show gathering locations'), findsOneWidget);
    expect(find.text('Add to planned network'), findsNothing);
  });

  testWidgets(
    'quick-map menu clamps full dynamic labels at 200 percent text scale',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 940));
      const materialName =
          "Resplendent Dim Tree Spirit's Armor Reform Stone V with an "
          'intentionally complete planner lookup label without abbreviations '
          'or truncation';
      final harness = PlannerTestHarness(
        resolveMapLookup: (_) async => const PlannerMapLookupAvailability(
          materialName: materialName,
          hasManualGathering: true,
          manualResourceId: 'item:long-label',
          manualLocationCount: 123456789,
          hasWorkerNodes: true,
          workerResourceId: 'item:long-label',
          workerNodeCount: 987654321,
        ),
        addToGatherChecklist: (_) {},
      );
      addTearDown(harness.controller.dispose);
      await tester.pumpWidget(
        harness.bonusHost(textScaler: const TextScaler.linear(2)),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(PlannerActionKeys.mapLookupRegion('need:Sunrise Herb')),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      final manualAction = find.byKey(
        PlannerActionKeys.mapLookupAction(
          'need:Sunrise Herb',
          PlannerMapLookupSource.manualGathering.name,
        ),
      );
      final menuRect = tester.getRect(manualAction);
      expect(menuRect.width, greaterThan(360));
      expect(menuRect.left, greaterThanOrEqualTo(8));
      expect(menuRect.right, lessThanOrEqualTo(1192));

      const visibleLabels = <String>[
        'Show gathering locations',
        '123456789 mapped locations',
        'Add to checklist',
        'Keep it in your map checklist',
        'Add to planned network',
        '987654321 worker nodes available',
      ];
      for (final label in visibleLabels) {
        final textFinder = find.text(label);
        expect(textFinder, findsOneWidget, reason: label);
        final text = tester.widget<Text>(textFinder);
        expect(text.maxLines, isNull, reason: label);
        expect(text.overflow, isNot(TextOverflow.ellipsis), reason: label);
        expect(
          tester.renderObject<RenderParagraph>(textFinder).didExceedMaxLines,
          isFalse,
          reason: label,
        );
        final textRect = tester.getRect(textFinder);
        expect(textRect.left, greaterThanOrEqualTo(8), reason: label);
        expect(textRect.right, lessThanOrEqualTo(1192), reason: label);
      }
      expect(find.text(materialName), findsNothing);
      expect(find.text('Choose what you want to do'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('worker-only materials can enter the shared map checklist', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final added = <PlannerMapLookupAvailability>[];
    final harness = PlannerTestHarness(
      resolveMapLookup: (materialName) async => PlannerMapLookupAvailability(
        materialName: materialName,
        hasWorkerNodes: true,
        workerResourceId: 'sunrise-herb',
        workerNodeCount: 3,
      ),
      addToGatherChecklist: added.add,
    );
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump();

    await tester.tap(
      find.byKey(PlannerActionKeys.mapLookupRegion('need:Sunrise Herb')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text('Show gathering locations'), findsNothing);
    expect(find.text('Add to checklist'), findsOneWidget);
    expect(find.text('Add to planned network'), findsOneWidget);
    expect(find.text('3 worker nodes available'), findsOneWidget);
    await tester.tap(
      find.byKey(
        PlannerActionKeys.mapLookupAction(
          'need:Sunrise Herb',
          'addToGatherChecklist',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(added, hasLength(1));
    expect(added.single.workerResourceId, 'sunrise-herb');
  });

  testWidgets('long-press opens the same source-aware map menu', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(
      resolveMapLookup: (materialName) async => PlannerMapLookupAvailability(
        materialName: materialName,
        hasManualGathering: true,
        manualResourceId: 'sunrise-herb',
        manualLocationCount: 1,
      ),
    );
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump();

    final region = find.byKey(
      PlannerActionKeys.mapLookupRegion('need:Sunrise Herb'),
    );
    await tester.longPress(region);
    await tester.pumpAndSettle();

    expect(find.text('Show gathering locations'), findsOneWidget);
    expect(find.text('Add to planned network'), findsNothing);
  });

  testWidgets('rows without a mapped source do not open an empty menu', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(
      resolveMapLookup: (materialName) async =>
          PlannerMapLookupAvailability(materialName: materialName),
    );
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump();

    await tester.tap(
      find.byKey(PlannerActionKeys.mapLookupRegion('need:Sunrise Herb')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      findsNothing,
    );
    expect(find.text('Show gathering locations'), findsNothing);
    expect(find.text('Add to planned network'), findsNothing);
    expect(harness.mapLookupRequests, isEmpty);
  });

  testWidgets('expanded craft ingredients use the same quick-map workflow', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final resolvedNames = <String>[];
    final harness = PlannerTestHarness(
      resolveMapLookup: (materialName) async {
        resolvedNames.add(materialName);
        return PlannerMapLookupAvailability(
          materialName: materialName,
          hasWorkerNodes: true,
          workerResourceId: 'sunrise-herb',
        );
      },
    );
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(harness.plannerHost());
    await tester.pump();

    final region = find.byKey(
      PlannerActionKeys.mapLookupRegion(
        'queue:Intermediate Reagent:Sunrise Herb',
      ),
    );
    expect(region, findsOneWidget);
    await tester.tap(
      region,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(resolvedNames, <String>['Sunrise Herb']);
    expect(find.text('Show gathering locations'), findsNothing);
    expect(find.text('Add to planned network'), findsOneWidget);
  });
}
