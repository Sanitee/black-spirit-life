import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/features/appearance/planner_appearance_popover.dart';
import 'package:bdo_craft_planner_flutter/features/appearance/planner_size_title_action.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../planner/planner_test_fixture.dart';

void main() {
  testWidgets('idle title action is icon-only and reveals live sizing', (
    tester,
  ) async {
    final controller = _controller();
    final maximum = ValueNotifier(1.25);
    addTearDown(controller.dispose);
    addTearDown(maximum.dispose);
    var opened = 0;
    await tester.pumpWidget(
      _host(_action(controller, maximum, onOpen: () => opened++)),
    );
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.text('Planner size'), findsNothing);
    expect(find.text('100%'), findsNothing);
    final trigger = find.byKey(PlannerSizeTitleAction.triggerKey);
    final button = tester.widget<IconButton>(trigger);
    expect(button.tooltip, 'Planner size');
    expect(tester.getSize(trigger), const Size(36, 32));

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Planner size'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Full appearance settings'), findsNothing);
    final panel = tester.getRect(
      find.byKey(PlannerAppearancePopover.surfaceKey),
    );
    expect(panel.width, 260);
    expect(panel.height, lessThan(240));
    expect(panel.top, greaterThan(tester.getRect(trigger).bottom));
    final slider = find.byKey(PlannerAppearancePopover.sliderKey);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveTo(
      tester.getRect(slider).centerRight - const Offset(8, 0),
    );
    await tester.pump();
    expect(controller.plannerContentScale.value, 1.25);
    expect(controller.documentSnapshot.plannerContentScale, 1);
    await gesture.up();
    await tester.pump();
    expect(controller.documentSnapshot.plannerContentScale, 1.25);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.documentSnapshot.plannerContentScale, 1.24);
    await tester.tap(find.byKey(PlannerAppearancePopover.resetKey));
    await tester.pump();
    expect(controller.documentSnapshot.plannerContentScale, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Escape restores trigger focus, outside clicks keep field focus',
    (tester) async {
      final controller = _controller();
      final maximum = ValueNotifier(1.25);
      final fieldFocus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(maximum.dispose);
      addTearDown(fieldFocus.dispose);
      await tester.pumpWidget(
        _host(
          _action(controller, maximum),
          body: SizedBox(
            width: 180,
            child: TextField(
              key: const ValueKey('outside-field'),
              focusNode: fieldFocus,
            ),
          ),
        ),
      );
      final trigger = find.byKey(PlannerSizeTitleAction.triggerKey);
      final triggerFocus = tester.widget<IconButton>(trigger).focusNode!;
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      controller.previewPlannerContentScale(1.14);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsNothing);
      expect(triggerFocus.hasFocus, isTrue);
      expect(controller.documentSnapshot.plannerContentScale, 1.14);

      await tester.tap(trigger);
      await tester.pumpAndSettle();
      controller.previewPlannerContentScale(1.19);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('outside-field')));
      await tester.pump();
      expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsNothing);
      expect(fieldFocus.hasFocus, isTrue);
      expect(triggerFocus.hasFocus, isFalse);
      expect(controller.documentSnapshot.plannerContentScale, 1.19);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'same trigger toggles without an outside-dismiss reopening race',
    (tester) async {
      final controller = _controller();
      final maximum = ValueNotifier(1.25);
      addTearDown(controller.dispose);
      addTearDown(maximum.dispose);
      var opened = 0;
      await tester.pumpWidget(
        _host(_action(controller, maximum, onOpen: () => opened++)),
      );
      final trigger = find.byKey(PlannerSizeTitleAction.triggerKey);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsNothing);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(opened, 2);
      expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'fit cap updates live without replacing the requested preference',
    (tester) async {
      final controller = _controller();
      final maximum = ValueNotifier(1.25);
      addTearDown(controller.dispose);
      addTearDown(maximum.dispose);
      await tester.pumpWidget(_host(_action(controller, maximum)));
      final trigger = find.byKey(PlannerSizeTitleAction.triggerKey);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      controller.previewPlannerContentScale(1.2);
      maximum.value = 1.08;
      await tester.pump();
      expect(find.text('108%'), findsOneWidget);
      expect(controller.plannerContentScale.value, 1.2);
      expect(controller.documentSnapshot.plannerContentScale, 1);
      await tester.tap(trigger);
      await tester.pump();
      expect(controller.documentSnapshot.plannerContentScale, 1.2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('removing an open title action commits an unfinished preview', (
    tester,
  ) async {
    final controller = _controller();
    final maximum = ValueNotifier(1.25);
    addTearDown(controller.dispose);
    addTearDown(maximum.dispose);
    var showing = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return showing ? _action(controller, maximum) : const SizedBox();
          },
        ),
      ),
    );
    await tester.tap(find.byKey(PlannerSizeTitleAction.triggerKey));
    await tester.pumpAndSettle();
    controller.previewPlannerContentScale(1.17);
    await tester.pump();
    rebuild(() => showing = false);
    await tester.pump();
    expect(controller.documentSnapshot.plannerContentScale, 1.17);
    expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final theme in [
    SakuraNightGardenSpec.theme,
    IlluminatedLedgerSpec.theme,
    StandardSpec.theme,
  ]) {
    testWidgets('${theme.id} popup remains compact at enlarged text', (
      tester,
    ) async {
      final controller = _controller();
      final maximum = ValueNotifier(1.25);
      addTearDown(controller.dispose);
      addTearDown(maximum.dispose);
      await tester.pumpWidget(
        _host(_action(controller, maximum), theme: theme, textScale: 2),
      );
      final trigger = find.byKey(PlannerSizeTitleAction.triggerKey);
      final button = tester.widget<IconButton>(trigger);
      if (theme.isIlluminatedLedger) {
        expect(
          button.style!.foregroundColor!.resolve({}),
          const Color(0xFFFFF8EA),
          reason: 'Ledger title strip stays light-on-navy.',
        );
      }
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(
        find.byKey(PlannerAppearancePopover.surfaceKey),
      );
      expect(bounds.width, 260);
      expect(bounds.height, lessThan(360));
      expect(
        find.byKey(PlannerAppearancePopover.resetKey).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

PlannerApplicationController _controller() => PlannerTestHarness().controller;

Widget _action(
  PlannerApplicationController controller,
  ValueNotifier<double> maximum, {
  VoidCallback? onOpen,
}) => PlannerSizeTitleAction(
  controller: controller,
  maximum: maximum,
  onOpen: onOpen ?? () {},
);

Widget _host(
  Widget action, {
  Widget? body,
  ThemeSpec? theme,
  double textScale = 1,
}) {
  final spec = theme ?? SakuraNightGardenSpec.theme;
  return MaterialApp(
    theme: spec.materialTheme(),
    home: ThemeSpecScope(
      spec: spec,
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: AppOverlayCoordinatorHost(
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [const Spacer(), action]),
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: body),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
