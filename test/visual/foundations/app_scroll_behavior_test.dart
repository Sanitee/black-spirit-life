import 'package:bdo_craft_planner_flutter/visual/foundations/app_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('coarse mouse-wheel steps ease to their native destination', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pumpList(tester, controller: controller);

    await _wheel(tester, find.byKey(_listKey), 120);

    expect(controller.offset, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 35));
    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(120));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(120, 0.01));
  });

  testWidgets('reduced motion keeps Flutter native wheel movement immediate', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pumpList(tester, controller: controller, disableAnimations: true);

    await _wheel(tester, find.byKey(_listKey), 120);

    expect(controller.offset, closeTo(120, 0.01));
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.offset, closeTo(120, 0.01));
  });

  testWidgets('fine wheel input remains direct and does not add latency', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pumpList(tester, controller: controller);

    await _wheel(tester, find.byKey(_listKey), 8);

    expect(controller.offset, closeTo(8, 0.01));
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.offset, closeTo(8, 0.01));
  });

  testWidgets('rapid wheel steps accumulate into one destination', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pumpList(tester, controller: controller);

    await _wheel(tester, find.byKey(_listKey), 120);
    await _wheel(tester, find.byKey(_listKey), 120);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(240, 0.01));
  });

  testWidgets('a new wheel step keeps the in-flight motion continuous', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pumpList(tester, controller: controller);

    await _wheel(tester, find.byKey(_listKey), 120);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final afterFirstFrame = controller.offset;
    expect(afterFirstFrame, greaterThan(0));
    expect(afterFirstFrame, lessThan(120));

    await _wheel(tester, find.byKey(_listKey), 120);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.offset, greaterThan(afterFirstFrame));
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(240, 0.01));
  });

  testWidgets('nested scrollables animate only the resolver-selected list', (
    tester,
  ) async {
    final outerController = ScrollController();
    final innerController = ScrollController();
    addTearDown(outerController.dispose);
    addTearDown(innerController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
          body: ListView(
            key: const ValueKey<String>('outer-list'),
            controller: outerController,
            children: <Widget>[
              SizedBox(
                height: 220,
                child: ListView.builder(
                  key: const ValueKey<String>('inner-list'),
                  controller: innerController,
                  itemExtent: 48,
                  itemCount: 30,
                  itemBuilder: (context, index) => Text('Inner $index'),
                ),
              ),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      ),
    );

    await _wheel(tester, find.byKey(const ValueKey<String>('inner-list')), 120);
    await tester.pumpAndSettle();

    expect(innerController.offset, closeTo(120, 0.01));
    expect(outerController.offset, 0);
  });
}

const _listKey = ValueKey<String>('smooth-list');

Future<void> _pumpList(
  WidgetTester tester, {
  required ScrollController controller,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: ListView.builder(
            key: _listKey,
            controller: controller,
            itemExtent: 48,
            itemCount: 30,
            itemBuilder: (context, index) => Text('Item $index'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _wheel(WidgetTester tester, Finder target, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      viewId: tester.view.viewId,
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(target),
      scrollDelta: Offset(0, delta),
    ),
  );
}
