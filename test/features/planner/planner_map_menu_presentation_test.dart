import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_map_menu_presentation.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('All open emblems fit narrow ${spec.id} text $scale', (
        tester,
      ) async {
        configureApplicationTestSurface(
          tester,
          const Size(320, 480),
          textScaleFactor: scale,
        );
        final opened = <PlannerMapLookupRequest>[];
        final checklist = <PlannerGatherChecklistRequest>[];
        final network = <PlannerMapLookupAvailability>[];
        const availability = PlannerMapLookupAvailability(
          materialName: 'Test material',
          hasNpcVendors: true,
          npcVendorCount: 47,
          hasManualGathering: true,
          manualLocationCount: 300,
          manualResourceId: 'test:manual',
          hasWorkerNodes: true,
          workerNodeCount: 16,
          workerResourceId: 'test:worker',
        );
        await tester.pumpWidget(
          ThemeSpecScope(
            spec: spec,
            child: MaterialApp(
              theme: spec.materialTheme(),
              home: Scaffold(
                body: Center(
                  child: PlannerMapQuickLookupRegion(
                    materialName: 'Test material',
                    stableId: 'fixture',
                    externalActions: PlannerExternalActions(
                      openRecipeBook: (_) {},
                      copyName: (_) async {},
                      checkPrices: (_) async =>
                          throw StateError('Unexpected market request'),
                      resolveMapLookup: (_) async => availability,
                      openMapLookup: opened.add,
                      addToGatherChecklist: checklist.add,
                      addToPlannedNetwork: network.add,
                    ),
                    child: Container(
                      key: ValueKey('trigger'),
                      width: 40,
                      height: 40,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final semantics = tester.ensureSemantics();
        try {
          for (final (action, emblem, label) in [
            ('npcVendors', PlannerMapEmblem.npc, 'Show NPC vendors'),
            (
              'manualGathering',
              PlannerMapEmblem.gathering,
              'Show gathering locations',
            ),
            (
              'addToGatherChecklist',
              PlannerMapEmblem.checklist,
              'Add to to-do list',
            ),
            (
              'addToPlannedNetwork',
              PlannerMapEmblem.network,
              'Add to planned network',
            ),
          ]) {
            await tester.tap(
              find.byKey(const ValueKey('trigger')),
              buttons: kSecondaryMouseButton,
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
            final target = find.byKey(
              PlannerActionKeys.mapLookupAction('fixture', action),
            );
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            final itemRect = tester.getRect(target);
            expect(itemRect.left, greaterThanOrEqualTo(0));
            expect(itemRect.right, lessThanOrEqualTo(320));
            expect(itemRect.top, greaterThanOrEqualTo(0));
            expect(itemRect.bottom, lessThanOrEqualTo(480));
            final icon = tester.widget<PlannerMapActionEmblem>(
              find.descendant(
                of: target,
                matching: find.byType(PlannerMapActionEmblem),
              ),
            );
            expect(icon.emblem, emblem);
            final content = find.descendant(
              of: target,
              matching: find.byType(PlannerMapMenuLabel),
            );
            expect(
              find.descendant(of: content, matching: find.byType(DecoratedBox)),
              findsNothing,
            );
            expect(
              find.descendant(of: content, matching: find.byType(Tooltip)),
              findsNothing,
            );
            expect(
              tester.getSemantics(target).getSemanticsData().label,
              contains(label),
            );
            for (final e
                in find
                    .descendant(of: content, matching: find.byType(RichText))
                    .evaluate()) {
              expect(
                (e.renderObject! as RenderParagraph).didExceedMaxLines,
                isFalse,
              );
            }
            expect(find.byType(PopupMenuDivider), findsNWidgets(3));
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(find.byType(PlannerMapMenuLabel), findsNothing);
            expect(tester.takeException(), isNull);
          }
          expect(opened.map((r) => r.resourceId), [null, 'test:manual']);
          expect(checklist.single.availability, same(availability));
          expect(network.single, same(availability));
          await tester.longPress(find.byKey(const ValueKey('trigger')));
          await tester.pumpAndSettle();
          expect(find.byType(PlannerMapMenuLabel), findsNWidgets(4));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(PlannerMapMenuLabel), findsNothing);
          expect(opened, hasLength(2));
          expect(checklist, hasLength(1));
          expect(network, hasLength(1));
        } finally {
          semantics.dispose();
        }
      });
    }
  }
}
