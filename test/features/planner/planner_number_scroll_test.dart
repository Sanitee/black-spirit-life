import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_shared.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'planner_test_fixture.dart';

void main() {
  for (final spec in RetainedThemeRegistry.themes) {
    for (final shared in [false, true]) {
      testWidgets(
        'New amount fields do not restore list scroll ${spec.id} shared=$shared',
        (tester) async {
          final list = ScrollController();
          final texts = List.generate(
            60,
            (_) => TextEditingController(text: '0'),
          );
          addTearDown(list.dispose);
          addTearDown(() {
            for (final text in texts) {
              text.dispose();
            }
          });
          await tester.pumpWidget(
            MaterialApp(
              home: ThemeSpecScope(
                spec: spec,
                child: Scaffold(
                  body: SizedBox(
                    height: 320,
                    child: ListView.builder(
                      key: const PageStorageKey('planner-need-first'),
                      controller: list,
                      itemExtent: 84,
                      itemCount: texts.length,
                      itemBuilder: (context, index) => Row(
                        children: [
                          const SizedBox(width: 80),
                          Text('Ingredient $index'),
                          const SizedBox(width: 30),
                          SizedBox(
                            width: 82,
                            height: 38,
                            child: shared
                                ? AppTextField(
                                    controller: texts[index],
                                    semanticLabel: 'Amount $index',
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    minimumHeight: 38,
                                  )
                                : PlannerTextField(
                                    controller: texts[index],
                                    semanticLabel: 'Amount $index',
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    minimumHeight: 38,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.drag(find.byType(ListView), const Offset(0, -360));
          await tester.pumpAndSettle();
          expect(list.offset, greaterThan(300));
          list.jumpTo(1680);
          await tester.pump();
          for (var frame = 0; frame < 8; frame++) {
            for (final element in find.byType(EditableText).evaluate()) {
              final state =
                  (element as StatefulElement).state as EditableTextState;
              final RenderEditable render = state.renderEditable;
              expect(state.widget.style.color, spec.typography.body.color);
              expect(
                render.offset.pixels,
                0,
                reason:
                    'frame $frame: a one-digit amount has no horizontal scroll',
              );
            }
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(tester.takeException(), isNull);
          final verticalOffset = list.offset;
          await tester.enterText(
            find.byType(TextField).first,
            '123456789012345678901234567890',
          );
          await tester.pumpAndSettle();
          final editor = tester.state<EditableTextState>(
            find.byType(EditableText).first,
          );
          expect(
            editor.renderEditable.offset.pixels,
            greaterThan(0),
            reason: 'Long values still scroll while editing',
          );
          expect(list.offset, verticalOffset);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets('Need First keeps newly visible amounts stable ${spec.id}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1500, 940);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final harness = PlannerTestHarness();
      final names = List.generate(
        60,
        (i) => 'Material ${i.toString().padLeft(2, '0')}',
      );
      final plan = PlanResult(
        target: 'Scroll fixture',
        want: 1,
        steps: const [],
        empty: false,
        missing: [
          for (final name in names)
            MissingMaterial(
              name: name,
              key: name,
              category: 'Materials',
              need: 20,
              have: 0,
              missing: 20,
              choice: null,
              market: const MarketMaterialState(
                marketable: true,
                stock: 0,
                price: 0,
                buyable: 0,
                unavailable: 0,
                total: 0,
                status: 'missing',
                hasSourceInfo: false,
              ),
            ),
        ],
      );
      await tester.pumpWidget(
        AppOverlayCoordinatorHost(
          child: MaterialApp(
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: Scaffold(
                body: PlannerPlanColumns(
                  controller: harness.controller.active,
                  plan: plan,
                  externalActions: harness.actions,
                  allowCompletion: false,
                  queueTitle: 'Craft Queue',
                  needTitle: 'Need First',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final listFinder = find.byKey(
        const PageStorageKey<String>('planner-need-first'),
      );
      final list = tester.widget<ListView>(listFinder).controller!;
      expect(
        find.byType(EditableText).evaluate().length,
        lessThan(30),
        reason: 'Rows stay virtualized',
      );
      for (final offset in [500.0, 1400.0, 2500.0, 300.0]) {
        list.jumpTo(offset);
        await tester.pump();
        for (var frame = 0; frame < 12; frame++) {
          for (final element
              in find
                  .descendant(
                    of: listFinder,
                    matching: find.byType(EditableText),
                  )
                  .evaluate()) {
            final state =
                (element as StatefulElement).state as EditableTextState;
            expect(state.widget.style.color, spec.typography.body.color);
            expect(
              state.renderEditable.offset.pixels,
              0,
              reason: 'Amount must already be in place at frame $frame',
            );
          }
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await harness.controller.dispose();
    });
  }
}
