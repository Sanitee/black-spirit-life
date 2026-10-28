import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_interaction_frame.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppInteractionEdgePainter edge(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.foregroundPainter)
      .whereType<AppInteractionEdgePainter>()
      .single;

  Widget host(
    Widget child, {
    bool reduced = false,
    bool accessible = false,
    bool ticking = true,
  }) => MaterialApp(
    home: ThemeSpecScope(
      spec: SakuraNightGardenSpec.theme,
      child: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          accessibleNavigation: accessible,
        ),
        child: TickerMode(
          enabled: ticking,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );

  testWidgets(
    'finite hover is paint-only, geometry-stable and idle afterwards',
    (tester) async {
      var builds = 0;
      final child = Builder(
        builder: (_) {
          builds++;
          return const SizedBox(width: 140, height: 44, child: Text('Action'));
        },
      );
      await tester.pumpWidget(host(AppInteractionFrame(child: child)));
      final before = tester.getRect(find.byType(AppInteractionFrame));
      final buildCount = builds;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(before.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(edge(tester).light.value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(edge(tester).light.value, 1);
      expect(tester.getRect(find.byType(AppInteractionFrame)), before);
      expect(builds, buildCount);
      expect(tester.binding.transientCallbackCount, 0);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(edge(tester).light.value, 0);
      expect(tester.binding.transientCallbackCount, 0);
      await mouse.removePointer();
    },
  );

  testWidgets('keyboard focus remains on the child, activation fires once', (
    tester,
  ) async {
    final first = FocusNode(), second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    var activations = 0;
    await tester.pumpWidget(
      host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton.label(
              'First',
              focusNode: first,
              onPressed: () => activations++,
            ),
            AppButton.label('Second', focusNode: second, onPressed: () {}),
          ],
        ),
      ),
    );
    first.requestFocus();
    await tester.pumpAndSettle();
    expect(first.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activations, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(second.hasPrimaryFocus, isTrue);
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    expect(activations, 2);
    expect(tester.takeException(), isNull);
  });

  for (final mode in ['reduced', 'accessible', 'hidden']) {
    testWidgets('$mode snaps feedback without a running ticker', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const AppInteractionFrame(child: SizedBox(width: 140, height: 44)),
          reduced: mode == 'reduced',
          accessible: mode == 'accessible',
          ticking: mode != 'hidden',
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(AppInteractionFrame)));
      await tester.pump();
      expect(edge(tester).light.value, 1);
      expect(tester.binding.transientCallbackCount, 0);
      await mouse.removePointer();
    });
  }

  testWidgets('disabled frame stays unlit and cannot consume its child hit', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      host(
        AppInteractionFrame(
          enabled: false,
          selected: true,
          child: GestureDetector(
            onTap: () => tapped++,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(width: 140, height: 44),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(AppInteractionFrame)));
    await tester.pumpAndSettle();
    expect(edge(tester).light.value, 0);
    expect(edge(tester).selected, isFalse);
    expect(edge(tester).hitTest(Offset.zero), isFalse);
    await tester.tap(find.byType(AppInteractionFrame));
    expect(tapped, 1);
    await mouse.removePointer();
  });

  testWidgets('disposal during an active transition leaves no ticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const AppInteractionFrame(child: SizedBox(width: 140, height: 44))),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(AppInteractionFrame)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
    await mouse.removePointer();
  });
}
