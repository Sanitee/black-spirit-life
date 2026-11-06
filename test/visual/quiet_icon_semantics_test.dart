import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final surface in ['application', 'gathering', 'map']) {
    for (final enabled in [true, false]) {
      testWidgets(
        '$surface quiet icon owns its accessible hint, enabled=$enabled',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            final focus = FocusNode();
            addTearDown(focus.dispose);
            var taps = 0;
            final onPressed = enabled ? () => taps++ : null;
            const key = ValueKey('quiet-close');
            const icon = Icon(Icons.close);
            final button = switch (surface) {
              'application' => QuietIconButton(
                key: key,
                tooltip: 'Close reference',
                focusNode: focus,
                onPressed: onPressed,
                icon: icon,
              ),
              'gathering' => GatheringQuietIconButton(
                key: key,
                tooltip: 'Close reference',
                focusNode: focus,
                onPressed: onPressed,
                icon: icon,
              ),
              _ => MapQuietIconButton(
                key: key,
                tooltip: 'Close reference',
                focusNode: focus,
                onPressed: onPressed,
                icon: icon,
              ),
            };
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: Row(
                    children: [
                      const Icon(Icons.science, semanticLabel: 'Neighbor item'),
                      const Text('Unrelated heading'),
                      button,
                    ],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final action = find.semantics.byPredicate(
              (node) =>
                  node.tooltip == 'Close reference' &&
                  node.getSemanticsData().flagsCollection.isButton,
            );
            expect(action.evaluate(), hasLength(1));
            final node = action.evaluate().single;
            expect(node.label, isNot(contains('Unrelated heading')));
            expect(node.label, isNot(contains('Neighbor item')));
            expect(
              node.getSemanticsData().flagsCollection.isEnabled,
              enabled ? ui.Tristate.isTrue : ui.Tristate.isFalse,
            );
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              enabled,
            );
            if (enabled) {
              tester.semantics.tap(action);
              expect(taps, 1);
              focus.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.space);
              expect(taps, 2);
            }
            final pointer = await tester.createGesture(
              kind: ui.PointerDeviceKind.mouse,
            );
            await pointer.addPointer(location: Offset.zero);
            addTearDown(pointer.removePointer);
            await pointer.moveTo(tester.getCenter(find.byKey(key)));
            await tester.pump(const Duration(seconds: 2));
            expect(find.text('Close reference'), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            handle.dispose();
          }
        },
      );
    }
  }
}
