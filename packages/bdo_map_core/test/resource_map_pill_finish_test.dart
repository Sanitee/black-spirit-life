import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    bool selected = false,
    bool quiet = false,
    bool reducedMotion = false,
    double opacity = .6,
    VoidCallback? onTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: ResourceMapChromeTheme(
            data: ResourceMapChromeThemeData.glassDock.withUiOpacity(opacity),
            child: ResourceMapReadingPlane(
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 184,
                    child: ResourceMapPill(
                      selected: selected,
                      quiet: quiet,
                      child: InkWell(
                        onTap: onTap ?? () {},
                        child: const SizedBox(
                          height: 50,
                          child: Text('Materials'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double fill(WidgetTester tester) =>
      ((tester
                          .widget<AnimatedContainer>(
                            find.byType(AnimatedContainer),
                          )
                          .decoration
                      as BoxDecoration)
                  .gradient!
              as LinearGradient)
          .colors
          .first
          .a;

  testWidgets('quiet shortcuts reduce backing without changing size or text', (
    tester,
  ) async {
    await open(tester);
    final normalFill = fill(tester);
    final bounds = tester.getRect(find.byType(ResourceMapPill));
    await open(tester, quiet: true);
    expect(fill(tester), closeTo(normalFill * .5, .0001));
    expect(tester.getRect(find.byType(ResourceMapPill)), bounds);
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('selected edge preserves child click and keyboard activation', (
    tester,
  ) async {
    var taps = 0;
    await open(tester, selected: true, onTap: () => taps++);
    final bounds = tester.getRect(find.byType(ResourceMapPill));
    await tester.tapAt(bounds.centerLeft + const Offset(3, 0));
    expect(
      taps,
      1,
      reason: 'The decorative selection edge must not intercept input.',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 2);
    expect(tester.getRect(find.byType(ResourceMapPill)), bounds);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover settles with no idle frames and no layout shift', (
    tester,
  ) async {
    await open(tester);
    final bounds = tester.getRect(find.byType(ResourceMapPill));
    final idleFill = fill(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(bounds.center);
    await tester.pumpAndSettle();
    expect(fill(tester), greaterThan(idleFill));
    expect(tester.getRect(find.byType(ResourceMapPill)), bounds);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(fill(tester), closeTo(idleFill, .0001));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion and zero opacity keep controls usable', (
    tester,
  ) async {
    var taps = 0;
    await open(
      tester,
      reducedMotion: true,
      opacity: 0,
      selected: true,
      onTap: () => taps++,
    );
    expect(
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
      Duration.zero,
    );
    await tester.tap(find.text('Materials'));
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
