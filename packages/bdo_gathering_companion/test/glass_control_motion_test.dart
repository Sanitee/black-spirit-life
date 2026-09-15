import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _controlKey = ValueKey('motion-control');

void main() {
  testWidgets('hover blends the glass finish and lifts without resizing', (
    tester,
  ) async {
    await _open(tester);
    final bounds = tester.getRect(find.byKey(_controlKey));
    final normal = _finish(tester);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(bounds.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final intermediate = _finish(tester);
    final hover = _glass(tester).hoverGradient;
    expect(intermediate.gradient, isNot(normal.gradient));
    expect(intermediate.gradient, isNot(hover));
    await tester.pumpAndSettle();
    expect(_finish(tester).gradient, hover);
    expect(_lift(tester), -1);
    expect(tester.getRect(find.byKey(_controlKey)), bounds);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(_finish(tester), normal);
    expect(_lift(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('press cancellation restores the face without activating', (
    tester,
  ) async {
    var calls = 0;
    await _open(tester, onPressed: () => calls++);
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_controlKey)),
    );
    await tester.pumpAndSettle();
    expect(_scale(tester), .985);
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    expect(calls, 0);
    await tester.tap(find.byKey(_controlKey));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('the lifted face keeps the original complete hit area', (
    tester,
  ) async {
    var calls = 0;
    await _open(
      tester,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => calls++,
        child: const SizedBox(width: 120, height: 52, child: Text('Prepare')),
      ),
    );
    final bounds = tester.getRect(find.byKey(_controlKey));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(bounds.center);
    await tester.pumpAndSettle();
    expect(_lift(tester), -1);
    await tester.tapAt(Offset(bounds.center.dx, bounds.bottom - .25));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('secondary click keeps its action without a primary press dip', (
    tester,
  ) async {
    var secondaryCalls = 0;
    await _open(
      tester,
      child: GestureDetector(
        onSecondaryTap: () => secondaryCalls++,
        child: const SizedBox(width: 120, height: 52, child: Text('Item info')),
      ),
    );
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(_controlKey)),
      kind: ui.PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(secondaryCalls, 1);
  });

  testWidgets('keyboard focus shares the finish without another focus stop', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var calls = 0;
    await _open(tester, focusNode: focus, onPressed: () => calls++);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, focus);
    expect(_finish(tester).gradient, _glass(tester).hoverGradient);
    expect(_lift(tester), -1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('disabled buttons neither lift nor activate', (tester) async {
    await _open(
      tester,
      child: const TextButton(onPressed: null, child: Text('Unavailable')),
    );
    final normal = _finish(tester);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(_controlKey)));
    await tester.pumpAndSettle();
    expect(_finish(tester), normal);
    expect(_lift(tester), 0);
    await mouse.down(tester.getCenter(find.byKey(_controlKey)));
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps feedback with no movement or transition', (
    tester,
  ) async {
    await _open(tester, reducedMotion: true);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(_controlKey)));
    await tester.pumpAndSettle();
    expect(_finish(tester).gradient, _glass(tester).hoverGradient);
    expect(_lift(tester), 0);
    final animation = tester.widget<TweenAnimationBuilder<Decoration>>(
      find.byKey(const ValueKey('glass-control-finish')),
    );
    expect(animation.duration, Duration.zero);
    await mouse.down(tester.getCenter(find.byKey(_controlKey)));
    await tester.pumpAndSettle();
    expect(_scale(tester), 1);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('selection blends to its final finish and stops repainting', (
    tester,
  ) async {
    await _open(tester);
    final normal = _finish(tester);
    await _open(tester, selected: true, settle: false);
    await tester.pump(const Duration(milliseconds: 70));
    expect(_finish(tester).gradient, isNot(normal.gradient));
    expect(_finish(tester).gradient, isNot(_glass(tester).selectedGradient));
    await tester.pumpAndSettle();
    expect(_finish(tester).gradient, _glass(tester).selectedGradient);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

Future<void> _open(
  WidgetTester tester, {
  VoidCallback? onPressed,
  FocusNode? focusNode,
  Widget? child,
  bool selected = false,
  bool reducedMotion = false,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: companionTheme(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: Center(
            child: GlassControl(
              key: _controlKey,
              selected: selected,
              child:
                  child ??
                  TextButton(
                    focusNode: focusNode,
                    onPressed: onPressed ?? () {},
                    child: const Text('Prepare'),
                  ),
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder _inside(Type type) => find
    .descendant(of: find.byKey(_controlKey), matching: find.byType(type))
    .first;

BoxDecoration _finish(WidgetTester tester) =>
    tester.widget<Ink>(_inside(Ink)).decoration! as BoxDecoration;

CompanionGlassTheme _glass(WidgetTester tester) =>
    tester.element(find.byKey(_controlKey)).glass;

double _lift(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byKey(const ValueKey('glass-control-lift')),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .storage[13];

double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(_inside(AnimatedScale)).scale;
