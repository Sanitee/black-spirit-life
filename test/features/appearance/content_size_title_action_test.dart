import 'package:bdo_craft_planner_flutter/features/appearance/content_size_popover.dart';
import 'package:bdo_craft_planner_flutter/features/appearance/content_size_title_action.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shared title sizing keeps icon-only geometry and commits only completed input',
    (tester) async {
      final value = ValueNotifier(1.0);
      final maximum = ValueNotifier(1.25);
      final outside = FocusNode();
      addTearDown(value.dispose);
      addTearDown(maximum.dispose);
      addTearDown(outside.dispose);
      const keys = ContentSizePopoverKeys('opportunities-appearance');
      const trigger = ValueKey('opportunities-size-title-action');
      var committed = 1.0;
      var commits = 0;
      Widget host() => MaterialApp(
        home: ThemeSpecScope(
          spec: SakuraNightGardenSpec.theme,
          child: AppOverlayCoordinatorHost(
            child: Scaffold(
              body: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: ContentSizeTitleAction(
                      label: 'Opportunities size',
                      overlayId: 'opportunities-size',
                      triggerKey: trigger,
                      popoverKeys: keys,
                      scale: value,
                      maximum: maximum,
                      onPreview: (next) => value.value = next,
                      onCommit: () {
                        committed = value.value;
                        commits++;
                      },
                      onReset: () {
                        value.value = 1;
                        committed = 1;
                      },
                    ),
                  ),
                  const SizedBox(height: 300),
                  TextField(key: const ValueKey('outside'), focusNode: outside),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host());
      expect(find.text('Opportunities size'), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(tester.getSize(find.byKey(trigger)), const Size(36, 32));
      await tester.tap(find.byKey(trigger));
      await tester.pumpAndSettle();
      expect(find.text('Opportunities size'), findsOneWidget);
      expect(tester.getSize(find.byKey(keys.surface)).width, 260);
      expect(tester.getSize(find.byKey(keys.surface)).height, lessThan(240));
      final slider = find.byKey(keys.slider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveTo(
        tester.getRect(slider).centerRight - const Offset(8, 0),
      );
      await tester.pump();
      expect(value.value, 1.25);
      expect(committed, 1);
      await gesture.up();
      await tester.pump();
      expect(committed, 1.25);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(committed, 1.24);
      maximum.value = 1.05;
      await tester.pump();
      expect(find.text('105%'), findsOneWidget);
      expect(
        value.value,
        1.24,
        reason: 'A fit cap must not overwrite the saved preference.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(keys.surface), findsNothing);
      expect(
        tester.widget<IconButton>(find.byKey(trigger)).focusNode!.hasFocus,
        isTrue,
      );
      await tester.tap(find.byKey(trigger));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('outside')));
      await tester.pumpAndSettle();
      expect(outside.hasFocus, isTrue);
      expect(find.byKey(keys.surface), findsNothing);
      await tester.tap(find.byKey(trigger));
      await tester.pumpAndSettle();
      value.value = 1.18;
      await tester.pump();
      final beforeRemoval = commits;
      await tester.pumpWidget(const SizedBox());
      expect(committed, 1.18);
      expect(commits, greaterThan(beforeRemoval));
    },
  );
}
