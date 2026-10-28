import 'dart:ui' show PointerDeviceKind;

import 'package:bdo_craft_planner_flutter/features/planner/planner_shared.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  testWidgets('optional clear keeps Tab empty but retains arrow selection', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(900, 700));
    final harness = PlannerTestHarness();
    addTearDown(harness.controller.dispose);
    final selected = <String>[];
    await tester.pumpWidget(
      _host(
        harness,
        allowEmptySelection: true,
        fieldBuilder: _customField,
        onSelected: (name) {
          selected.add(name);
          return true;
        },
      ),
    );
    final field = find.byType(TextField);
    await tester.enterText(field, 'Sunrise');
    await tester.pump();
    expect(_popup(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clear-test-choice')));
    await tester.pumpAndSettle();
    expect(selected.last, isEmpty);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(_popup(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(selected.every((value) => value.isEmpty), isTrue);
    await tester.tap(field);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(selected.last, 'Silver Azalea');
    expect(tester.widget<TextField>(field).controller!.text, 'Silver Azalea');
    expect(_popup(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default chooser keeps Planner copy, dimensions and artwork', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(900, 700));
    final harness = PlannerTestHarness();
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(_host(harness));
    expect(find.byKey(const ValueKey('clear-test-choice')), findsNothing);
    final field = find.byType(TextField);
    expect(
      tester.widget<TextField>(field).decoration?.hintText,
      'Search craftable recipes',
    );
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(tester.getSize(_popup()).width, 460);
    expect(tester.getSize(_popup()).height, 148);
    expect(find.byType(PlannerItemIcon), findsNWidgets(2));
    expect(
      tester.widget<PlannerItemIcon>(find.byType(PlannerItemIcon).first).size,
      42,
    );
    await tester.enterText(field, 'No such recipe');
    await tester.pump();
    expect(find.text('No matching craftable recipes'), findsOneWidget);
    expect(tester.getSize(_popup()).height, 82);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'custom material choice uses its setter without changing Planner',
    (tester) async {
      await setPlannerTestSize(tester, const Size(900, 700));
      final harness = PlannerTestHarness();
      addTearDown(harness.controller.dispose);
      final before = harness.controller.documentSnapshot;
      final selected = <String>[];
      await tester.pumpWidget(
        _host(
          harness,
          hintText: 'Find an item',
          emptyText: 'No matching items',
          popupWidth: 320,
          popupMaxHeight: 140,
          onSelected: (name) {
            // Match the material setter's equal-value guard. The existing
            // chooser may commit the same text again when focus changes.
            if (selected.isEmpty || selected.last != name) selected.add(name);
            return true;
          },
          itemIconBuilder: (context, name) => ModeItemIcon(
            key: ValueKey<String>('material-icon:$name'),
            controller: harness.controller.active,
            name: name,
            size: 36,
            searchAcrossModes: true,
          ),
        ),
      );
      final field = find.byType(TextField);
      expect(
        tester.widget<TextField>(field).decoration?.hintText,
        'Find an item',
      );
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(tester.getSize(_popup()), const Size(320, 140));
      expect(find.byType(PlannerItemIcon), findsNothing);
      final icon = tester.widget<ModeItemIcon>(
        find.byKey(const ValueKey<String>('material-icon:Sunrise Herb')),
      );
      expect(icon.searchAcrossModes, isTrue);
      expect(icon.size, 36);
      final mouse = await tester.startGesture(
        tester.getCenter(_option('Sunrise Herb')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(selected, <String>['Sunrise Herb']);
      expect(_popup(), findsNothing);
      expect(tester.widget<TextField>(field).controller?.text, 'Sunrise Herb');
      expect(identical(harness.controller.documentSnapshot, before), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom chooser retains keyboard selection and Escape', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(900, 700));
    final harness = PlannerTestHarness();
    addTearDown(harness.controller.dispose);
    final selected = <String>[];
    await tester.pumpWidget(
      _host(
        harness,
        names: const <String>['Silver Azalea', 'Sunrise Herb'],
        hintText: 'Find an item',
        onSelected: (name) {
          if (selected.isEmpty || selected.last != name) selected.add(name);
          return true;
        },
      ),
    );
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(selected, <String>['Sunrise Herb']);
    expect(_popup(), findsNothing);
    await tester.tap(field);
    await tester.pump();
    expect(_popup(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_popup(), findsNothing);
    expect(selected, <String>['Sunrise Herb']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a caller can bound the popup below the old minimum height', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(600, 400));
    final harness = PlannerTestHarness();
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(
      _host(harness, popupWidth: 280, popupMaxHeight: 60),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.getSize(_popup()), const Size(280, 60));
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enlarged labels remain bounded inside custom option rows', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(600, 600));
    final harness = PlannerTestHarness();
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(
      _host(
        harness,
        names: const <String>['Intermediate Reagent', 'Pure Powder Reagent'],
        textScaler: const TextScaler.linear(2),
        popupWidth: 320,
        popupMaxHeight: 180,
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final popup = tester.getRect(_popup());
    expect(popup.width, 320);
    expect(popup.height, lessThanOrEqualTo(180));
    expect(popup.right, lessThanOrEqualTo(600));
    expect(popup.bottom, lessThanOrEqualTo(600));
    final option = _option('Intermediate Reagent');
    final row = tester.getRect(option);
    final label = tester.getRect(
      find.descendant(of: option, matching: find.text('Intermediate Reagent')),
    );
    expect(label.left, greaterThanOrEqualTo(row.left));
    expect(label.right, lessThanOrEqualTo(row.right));
    expect(label.top, greaterThanOrEqualTo(row.top));
    expect(label.bottom, lessThanOrEqualTo(row.bottom));
    expect(row.height, greaterThan(60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom empty copy never selects an unknown item', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(600, 500));
    final harness = PlannerTestHarness();
    addTearDown(harness.controller.dispose);
    final selected = <String>[];
    await tester.pumpWidget(
      _host(
        harness,
        hintText: 'Find an item',
        emptyText: 'No matching items',
        popupWidth: 320,
        popupMaxHeight: 110,
        textScaler: const TextScaler.linear(2),
        onSelected: (name) {
          if (!const <String>['Sunrise Herb', 'Silver Azalea'].contains(name)) {
            return false;
          }
          selected.add(name);
          return true;
        },
      ),
    );
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, 'Not a material');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('No matching items'), findsOneWidget);
    expect(find.text('No matching craftable recipes'), findsNothing);
    expect(selected, isEmpty);
    expect(tester.getSize(_popup()).height, lessThanOrEqualTo(110));
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom field and option builders retain mouse selection', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(900, 700));
    final harness = PlannerTestHarness();
    addTearDown(harness.controller.dispose);
    final before = harness.controller.documentSnapshot;
    final selected = <String>[];
    await tester.pumpWidget(
      _host(
        harness,
        fieldBuilder: _customField,
        optionBuilder: _customOption,
        onSelected: (name) {
          if (selected.isEmpty || selected.last != name) selected.add(name);
          return true;
        },
      ),
    );
    final field = find.byKey(const ValueKey<String>('custom-field'));
    expect(find.byType(PlannerTextField), findsNothing);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.byType(PlannerItemIcon), findsNothing);
    final option = find.byKey(const ValueKey<String>('custom:Sunrise Herb'));
    expect(tester.widget<AppButton>(option).selected, isTrue);
    final mouse = await tester.startGesture(
      tester.getCenter(option),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    expect(selected, <String>['Sunrise Herb']);
    expect(_popup(), findsNothing);
    expect(tester.widget<TextField>(field).controller?.text, 'Sunrise Herb');
    expect(identical(harness.controller.documentSnapshot, before), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'custom builders retain filtering, highlight, submit and Escape',
    (tester) async {
      await setPlannerTestSize(tester, const Size(900, 700));
      final harness = PlannerTestHarness();
      addTearDown(harness.controller.dispose);
      final selected = <String>[];
      await tester.pumpWidget(
        _host(
          harness,
          fieldBuilder: _customField,
          optionBuilder: _customOption,
          onSelected: (name) {
            if (selected.isEmpty || selected.last != name) selected.add(name);
            return true;
          },
        ),
      );
      final field = find.byKey(const ValueKey<String>('custom-field'));
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        tester
            .widget<AppButton>(
              find.byKey(const ValueKey<String>('custom:Silver Azalea')),
            )
            .selected,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_popup(), findsNothing);
      await tester.enterText(field, 'Silver');
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('custom:Sunrise Herb')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('custom:Silver Azalea')),
        findsOneWidget,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(selected, <String>['Silver Azalea']);
      expect(_popup(), findsNothing);
      expect(tester.widget<TextField>(field).controller?.text, 'Silver Azalea');
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _customOption(
  BuildContext context,
  String name,
  bool selected,
  VoidCallback onSelected,
) => AppButton(
  key: ValueKey<String>('custom:$name'),
  selected: selected,
  onPressed: onSelected,
  child: Text(name),
);

Widget _customField(
  BuildContext context,
  TextEditingController controller,
  FocusNode focusNode,
  ValueChanged<String> onChanged,
  VoidCallback onTap,
  ValueChanged<String> onSubmitted,
  FocusOnKeyEventCallback onKeyEvent,
  VoidCallback? onClear,
) => Focus(
  onKeyEvent: onKeyEvent,
  child: TextField(
    key: const ValueKey<String>('custom-field'),
    controller: controller,
    focusNode: focusNode,
    onChanged: onChanged,
    onTap: onTap,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      hintText: 'Custom item field',
      suffixIcon: onClear == null
          ? null
          : IconButton(
              key: const ValueKey('clear-test-choice'),
              onPressed: onClear,
              icon: const Icon(Icons.close),
            ),
    ),
  ),
);

Finder _popup() => find.byWidgetPredicate(
  (widget) =>
      widget is AppSurface && widget.semanticLabel == 'Choose item choices',
);

Finder _option(String name) => find.byWidgetPredicate(
  (widget) => widget is AppButton && widget.semanticLabel == 'Select $name',
);

Widget _host(
  PlannerTestHarness harness, {
  List<String> names = const <String>['Sunrise Herb', 'Silver Azalea'],
  bool Function(String)? onSelected,
  String hintText = 'Search craftable recipes',
  String emptyText = 'No matching craftable recipes',
  double popupWidth = 460,
  double popupMaxHeight = 420,
  TextScaler textScaler = TextScaler.noScaling,
  Widget Function(BuildContext, String)? itemIconBuilder,
  PlannerTargetOptionBuilder? optionBuilder,
  PlannerTargetFieldBuilder? fieldBuilder,
  bool allowEmptySelection = false,
}) => AppOverlayCoordinatorHost(
  child: MaterialApp(
    theme: StandardSpec.theme.materialTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: ThemeSpecScope(
      spec: StandardSpec.theme,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: popupWidth,
              child: PlannerTargetChooser(
                controller: harness.controller.active,
                target: PlannerCommandTarget(
                  value: '',
                  names: names,
                  onSelected: onSelected ?? (_) => false,
                ),
                semanticLabel: 'Choose item',
                actionKey: const ValueKey<String>('test-item-choice'),
                hintText: hintText,
                emptyText: emptyText,
                popupWidth: popupWidth,
                popupMaxHeight: popupMaxHeight,
                itemIconBuilder: itemIconBuilder,
                optionBuilder: optionBuilder,
                fieldBuilder: fieldBuilder,
                allowEmptySelection: allowEmptySelection,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
