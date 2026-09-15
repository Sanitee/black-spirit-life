import 'package:bdo_gathering_companion/src/ui/expedition_chrome.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'stage reveal preserves editor state with reduced motion $reducedMotion',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var stage = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: child!,
            ),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: GatheringStageReveal(
                  key: const ValueKey('workflow-stage-reveal'),
                  stage: stage,
                  child: Column(
                    children: [
                      TextButton(
                        key: const ValueKey('change-stage'),
                        onPressed: () => setState(() => stage++),
                        child: const Text('Next stage'),
                      ),
                      TextField(
                        key: const ValueKey('retained-editor'),
                        controller: controller,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final editor = find.byKey(const ValueKey('retained-editor'));
        await tester.enterText(editor, 'Saved draft');
        final editorState = tester.state(find.byType(EditableText));
        await tester.tap(find.byKey(const ValueKey('change-stage')));
        await tester.pump();
        final reveal = find.byKey(const ValueKey('workflow-stage-reveal'));
        final fade = find.descendant(
          of: reveal,
          matching: find.byType(FadeTransition),
        );
        final slide = find.descendant(
          of: reveal,
          matching: find.byType(SlideTransition),
        );
        expect(fade, findsOneWidget);
        expect(slide, findsOneWidget);
        expect(
          tester.widget<FadeTransition>(fade).opacity.value,
          reducedMotion ? equals(1) : lessThan(1),
        );
        expect(
          tester.widget<SlideTransition>(slide).position.value,
          reducedMotion ? Offset.zero : isNot(Offset.zero),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
        expect(
          tester.widget<SlideTransition>(slide).position.value,
          Offset.zero,
        );
        expect(tester.state(find.byType(EditableText)), same(editorState));
        expect(controller.text, 'Saved draft');
        expect(editor, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'glass control keeps hover, keyboard focus and click with reduced motion $reducedMotion',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var actions = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: GlassControl(
                  key: const ValueKey('interactive-glass'),
                  child: InkWell(
                    focusNode: focus,
                    onTap: () => actions++,
                    child: const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Gather'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final control = find.byKey(const ValueKey('interactive-glass'));
        final face = find.descendant(
          of: control,
          matching: find.byType(AnimatedContainer),
        );
        final press = find.descendant(
          of: control,
          matching: find.byType(AnimatedScale),
        );
        BoxDecoration decoration() =>
            tester.widget<AnimatedContainer>(face).decoration! as BoxDecoration;
        final duration = reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 160);
        expect(decoration().boxShadow, hasLength(1));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(control));
        await tester.pumpAndSettle();
        expect(decoration().boxShadow, hasLength(2));
        expect(tester.widget<AnimatedContainer>(face).duration, duration);
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expect(decoration().boxShadow, hasLength(1));

        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect(decoration().boxShadow!.first.spreadRadius, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(actions, 1);

        final gesture = await tester.startGesture(tester.getCenter(control));
        await tester.pump();
        expect(tester.widget<AnimatedScale>(press).scale, reducedMotion ? 1 : .985);
        expect(tester.widget<AnimatedScale>(press).duration, duration);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(actions, 2);
        expect(tester.widget<AnimatedScale>(press).scale, 1);
        final cancelled = await tester.startGesture(tester.getCenter(control));
        await tester.pump();
        await cancelled.cancel();
        await tester.pumpAndSettle();
        expect(actions, 2);
        expect(tester.widget<AnimatedScale>(press).scale, 1);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
