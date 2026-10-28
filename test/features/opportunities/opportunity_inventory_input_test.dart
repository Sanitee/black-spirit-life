import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/inventory_storage.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_inventory_input.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../inventory/inventory_test_fixture.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('owned amount is a number-only icon footer at $scale', (
      tester,
    ) async {
      final h = InventoryTestHarness();
      addTearDown(h.controller.dispose);
      addTearDown(h.dispose);
      h.controller.active.commitInventory('Sunrise Herb', '0');
      await tester.pumpWidget(_host(h, textScale: scale));

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Inventory'), findsNothing);
      expect(find.text('0'), findsOneWidget);
      final amount = tester.getRect(find.text('0'));
      final icon = tester.getRect(find.byKey(const ValueKey('test-item-icon')));
      final control = tester.getRect(find.byType(OpportunityInventoryInput));
      expect(amount.top, greaterThanOrEqualTo(icon.bottom));
      expect(amount.center.dx, closeTo(icon.center.dx, 1));
      expect(control.height, lessThanOrEqualTo(80 * scale));
      expect(control.width, closeTo(icon.width, 1));
      final frame = find.byKey(const ValueKey('inventory-amount-frame'));
      final emptySize = tester.getSize(frame);
      await tester.tap(_amountButton);
      await tester.pump();
      expect(tester.getSize(frame).height, emptySize.height);
      expect(
        tester.getSize(frame).width,
        greaterThanOrEqualTo(emptySize.width),
      );
      await tester.enterText(find.byType(TextField), '2200');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tester.getSize(frame).height, emptySize.height);
      expect(
        tester.getSize(frame).width,
        greaterThanOrEqualTo(emptySize.width),
      );
      expect(find.text('2.2k'), findsOneWidget);

      h.controller.active.commitInventory('Sunrise Herb', '1000000');
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('1M'), findsOneWidget);
      _expectAccessibleAmount(tester, '1.000.000');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(_amountButton));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(Tooltip), findsNothing);
      expect(find.text('1.000.000'), findsNothing);
      await mouse.removePointer();
      expect(
        tester.getSize(find.byType(OpportunityInventoryInput)).height,
        lessThanOrEqualTo(80 * scale),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('click to edit, group while typing and compact on Enter', (
    tester,
  ) async {
    final h = InventoryTestHarness();
    addTearDown(h.controller.dispose);
    addTearDown(h.dispose);
    h.controller.active.commitInventory('Sunrise Herb', '0');
    await tester.pumpWidget(_host(h));
    final field = find.byType(TextField);
    expect(field, findsNothing);
    await tester.tap(_amountButton);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '0');
    await tester.enterText(field, '400000');
    expect(tester.widget<TextField>(field).controller!.text, '400.000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(field, findsNothing);
    expect(find.text('400k'), findsOneWidget);
    for (final mode in CraftMode.values) {
      expect(
        h.controller.modes[mode]!.state.value.inventory['Sunrise Herb'],
        400000,
      );
    }
    await tester.tap(_amountButton);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '400.000');
    await tester.enterText(field, '1000000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(field, findsNothing);
    expect(find.text('1M'), findsOneWidget);
    _expectAccessibleAmount(tester, '1.000.000');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'shared screenshot amounts update the value; blur and close save edits',
    (tester) async {
      final h = InventoryTestHarness();
      addTearDown(h.controller.dispose);
      addTearDown(h.dispose);
      await tester.pumpWidget(_host(h));
      h.controller.updateDocument(
        (document) =>
            setSharedInventoryAmounts(document, {'Sunrise Herb': 123456}),
      );
      await tester.pump();
      final field = find.byType(TextField);
      expect(field, findsNothing);
      expect(find.text('123.4k'), findsOneWidget);
      await tester.tap(_amountButton);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '123.456');
      await tester.enterText(field, '12000');
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(h.controller.active.state.value.inventory['Sunrise Herb'], 12000);
      expect(field, findsNothing);
      expect(find.text('12k'), findsOneWidget);
      await tester.tap(_amountButton);
      await tester.pump();
      await tester.enterText(field, '76543');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(h.controller.active.state.value.inventory['Sunrise Herb'], 76543);
    },
  );

  testWidgets(
    'invalid, empty and paused edits preserve saved amounts; zero is valid',
    (tester) async {
      final h = InventoryTestHarness();
      addTearDown(h.controller.dispose);
      addTearDown(h.dispose);
      h.controller.active.commitInventory('Sunrise Herb', '50');
      await tester.pumpWidget(_host(h));
      final field = find.byType(TextField);
      await tester.tap(_amountButton);
      await tester.pump();
      for (final invalid in ['-5', '']) {
        await tester.enterText(field, invalid);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(h.controller.active.state.value.inventory['Sunrise Herb'], 50);
        expect(find.text('Use 0 or more'), findsOneWidget);
      }
      h.controller.freezeMutationsForRestart();
      await tester.enterText(field, '20');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(h.controller.active.state.value.inventory['Sunrise Herb'], 50);
      expect(find.text('Edits are paused'), findsOneWidget);
      h.controller.resumeMutationsAfterRestartFailure();
      await tester.enterText(field, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(h.controller.active.state.value.inventory['Sunrise Herb'], isNull);
      expect(field, findsNothing);
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final activation in [
    ('Enter', LogicalKeyboardKey.enter),
    ('Space', LogicalKeyboardKey.space),
  ]) {
    testWidgets('${activation.$1} edits focused amount; Escape cancels', (
      tester,
    ) async {
      final h = InventoryTestHarness();
      addTearDown(h.controller.dispose);
      addTearDown(h.dispose);
      h.controller.active.commitInventory('Sunrise Herb', '400000');
      await tester.pumpWidget(_host(h));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(activation.$2);
      await tester.pump();
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, '400.000');
      await tester.enterText(field, '999');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(field, findsNothing);
      expect(find.text('400k'), findsOneWidget);
      expect(h.controller.active.state.value.inventory['Sunrise Herb'], 400000);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(
        h.controller.active.state.value.inventory['Sunrise Herb'],
        400000,
        reason: 'A cancelled edit must not be saved later during disposal.',
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Finder get _amountButton =>
    find.byKey(const ValueKey('inventory-amount-button'));

void _expectAccessibleAmount(WidgetTester tester, String value) {
  final semantics = find.ancestor(
    of: _amountButton,
    matching: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Sunrise Herb inventory',
    ),
  );
  expect(semantics, findsOneWidget);
  final properties = tester.widget<Semantics>(semantics).properties;
  expect(properties.value, value);
  expect(properties.button, isTrue);
}

Widget _host(InventoryTestHarness h, {double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: ThemeSpecScope(
    spec: OpportunitiesVisualSpec.spec,
    child: Scaffold(
      body: Center(
        child: OpportunityInventoryInput(
          controller: h.controller.active,
          itemName: 'Sunrise Herb',
          iconBuilder: (size) => SizedBox.square(
            key: const ValueKey('test-item-icon'),
            dimension: size,
          ),
        ),
      ),
    ),
  ),
);
