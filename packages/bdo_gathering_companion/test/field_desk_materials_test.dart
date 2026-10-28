import 'package:bdo_gathering_companion/src/ui/field_desk_materials.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'session surface keeps focus, bounds and idle frames ($reduced)',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Center(
                  child: FieldDeskPanel(
                    interactive: true,
                    child: InkWell(
                      focusNode: focus,
                      onTap: () => calls++,
                      child: const SizedBox(
                        width: 240,
                        height: 70,
                        child: Text('Wolf session'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final surface = find.byType(FieldDeskPanel);
        final bounds = tester.getRect(surface);
        final element = tester.element(find.byType(InkWell));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(bounds.center);
        await tester.pumpAndSettle();
        expect(tester.getRect(surface), bounds);
        expect(tester.binding.hasScheduledFrame, isFalse);
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(InkWell)), same(element));
        expect(FocusManager.instance.primaryFocus, same(focus));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(calls, 1);
        final finish = tester.widget<AnimatedContainer>(
          find.descendant(
            of: surface,
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          finish.duration,
          reduced ? Duration.zero : const Duration(milliseconds: 150),
        );
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('desk surface adds no blur, opacity layer or recurring frames', (
    tester,
  ) async {
    var clicks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(opacityPercent: 90),
        home: Scaffold(
          body: Center(
            child: FieldDeskPanel(
              child: InkWell(
                onTap: () => clicks++,
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Session'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final panel = find.byType(FieldDeskPanel);
    expect(
      find.descendant(of: panel, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(Opacity)),
      findsNothing,
    );
    await tester.tap(find.text('Session'));
    await tester.pumpAndSettle();
    expect(clicks, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selection paint keeps editor identity, focus and pointer actions',
    (tester) async {
      final selected = ValueNotifier(false);
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(selected.dispose);
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: selected,
              builder: (context, active, _) => FieldDeskSelection(
                selected: active,
                child: SizedBox(
                  width: 240,
                  child: TextField(controller: controller, focusNode: focus),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '1735');
      final element = tester.element(find.byType(TextField));
      selected.value = true;
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(TextField)), same(element));
      expect(controller.text, '1735');
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 700.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('section heading stays usable at $width / $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var clicks = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: FieldDeskSectionHeading(
                title: 'Recommended Items',
                prominent: true,
                action: TextButton(
                  onPressed: () => clicks++,
                  child: const Text('Use basic kit'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Use basic kit'));
        await tester.pumpAndSettle();
        expect(clicks, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
