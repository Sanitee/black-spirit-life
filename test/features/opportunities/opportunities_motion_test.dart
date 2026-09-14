import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'card hover preserves size, clicks and keyboard; reduced=$reduced',
      (tester) async {
        var clicks = 0;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Center(
                  child: OpportunityCardMotion(
                    child: SizedBox(
                      key: const ValueKey('card'),
                      width: 320,
                      height: 140,
                      child: InkWell(
                        focusNode: focus,
                        onTap: () => clicks++,
                        child: const Text('Profit 12M'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('card'));
        final original = tester.getRect(card);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(original.center);
        await tester.pumpAndSettle();
        final hovered = tester.getRect(card);
        expect(hovered.size, original.size);
        expect(
          hovered,
          original,
          reason: 'Hover must not lift or resize cards.',
        );
        final motion = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(OpportunityCardMotion),
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(motion.transform, isNull);
        final finish = motion.foregroundDecoration! as BoxDecoration;
        expect(finish.gradient, isNull);
        expect(finish.boxShadow, isNull);
        expect(finish.color!.a, greaterThan(0));
        expect(finish.color!.a, lessThan(.04));
        expect(
          motion.duration,
          reduced ? Duration.zero : const Duration(milliseconds: 140),
        );
        expect(tester.binding.transientCallbackCount, 0);
        await tester.tapAt(Offset(original.center.dx, original.bottom - .5));
        await tester.pumpAndSettle();
        expect(
          clicks,
          1,
          reason: 'The stationary finish must keep the full card clickable.',
        );
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(clicks, 2);
        await mouse.moveTo(Offset.zero);
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(tester.getRect(card), original);
        final focused = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(OpportunityCardMotion),
            matching: find.byType(AnimatedContainer),
          ),
        );
        final focusedFinish = focused.foregroundDecoration! as BoxDecoration;
        expect(
          (focusedFinish.border! as Border).top.color,
          OpportunitiesVisualSpec.palette.primaryBright,
        );
        expect(focusedFinish.boxShadow, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(clicks, 3);
        expect(find.text('Profit 12M'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('reduced-motion entrance is visible immediately and idle', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: OpportunityEntrance(child: Text('Oil of the Abyss')),
        ),
      ),
    );
    final fade = tester.widget<FadeTransition>(
      find.byType(FadeTransition).last,
    );
    final slide = tester.widget<SlideTransition>(
      find.byType(SlideTransition).last,
    );
    expect(fade.opacity.value, 1);
    expect(slide.position.value, Offset.zero);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a completed entrance does not replay when its content updates', (
    tester,
  ) async {
    Widget host(String label) => MaterialApp(
      home: OpportunityEntrance(
        key: const ValueKey('same-recipe'),
        child: Text(label),
      ),
    );
    await tester.pumpWidget(host('Profit 12M'));
    await tester.pump(const Duration(milliseconds: 60));
    final entrance = find.byKey(const ValueKey('same-recipe'));
    FadeTransition fade() => tester.widget<FadeTransition>(
      find.descendant(of: entrance, matching: find.byType(FadeTransition)),
    );
    expect(fade().opacity.value, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(fade().opacity.value, 1);
    await tester.pumpWidget(host('Profit 13M'));
    expect(find.text('Profit 13M'), findsOneWidget);
    expect(fade().opacity.value, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabling reduced motion finishes an in-flight entrance', (
    tester,
  ) async {
    Widget host(bool reduced) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const OpportunityEntrance(
          key: ValueKey('same-recipe'),
          child: Text('Black Gem'),
        ),
      ),
    );
    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 60));
    final entrance = find.byKey(const ValueKey('same-recipe'));
    FadeTransition fade() => tester.widget<FadeTransition>(
      find.descendant(of: entrance, matching: find.byType(FadeTransition)),
    );
    expect(fade().opacity.value, inExclusiveRange(0, 1));
    await tester.pumpWidget(host(true));
    expect(fade().opacity.value, 1);
    expect(
      tester
          .widget<SlideTransition>(
            find.descendant(
              of: entrance,
              matching: find.byType(SlideTransition),
            ),
          )
          .position
          .value,
      Offset.zero,
    );
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(false));
    expect(fade().opacity.value, 1);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
