import 'dart:ui' show PointerDeviceKind;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_inventory_input.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_view.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  test('owned quantities abbreviate without rounding up', () {
    for (final entry in <double, String>{
      0: '0',
      999: '999',
      999.125: '999,125',
      1000: '1k',
      25430: '25.4k',
      25999: '25.9k',
      999999: '999.9k',
      1000000: '1M',
      1234567: '1.2M',
      1000000000: '1B',
    }.entries) {
      expect(formatPlannerInventoryAmount(entry.key), entry.value);
    }
  });

  for (final spec in [
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
    SakuraNightGardenSpec.theme,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'quantity footer attaches beneath the icon in ${spec.id} at $scale',
        (tester) async {
          final h = PlannerTestHarness();
          addTearDown(h.controller.dispose);
          h.controller.active.commitInventory(_name, '25430');
          await tester.pumpWidget(_host(h, spec: spec, textScale: scale));
          expect(find.byType(TextField), findsNothing);
          expect(find.byType(InputDecorator), findsNothing);
          expect(find.text('25.4k'), findsOneWidget);
          expect(find.byTooltip('25.430'), findsOneWidget);
          expect(find.text('Inventory'), findsNothing);
          final amount = tester.getRect(find.text('25.4k'));
          final icon = tester.getRect(
            find.byKey(const ValueKey('planner-inventory-icon-$_name')),
          );
          final footer = tester.getRect(
            find.byKey(const ValueKey('planner-inventory-footer-$_name')),
          );
          final control = tester.getRect(find.byType(PlannerInventoryInput));
          expect(footer.top, closeTo(icon.bottom, .1));
          expect(footer.left, closeTo(icon.left, .1));
          expect(footer.width, closeTo(icon.width, .1));
          expect(amount.center.dx, closeTo(icon.center.dx, .1));
          expect(control.height, lessThanOrEqualTo(icon.height + 30 * scale));
          expect(control.width, closeTo(icon.width, .1));
          await tester.tap(
            find.byKey(const ValueKey('planner-inventory-icon-$_name')),
          );
          await tester.pump();
          expect(
            find.byType(TextField),
            findsNothing,
            reason: 'Only the footer, not the artwork, activates editing.',
          );
          await tester.tap(_amount);
          await tester.pump();
          expect(_text(tester), '25.430');
          await tester.enterText(find.byType(TextField), '1000000000');
          expect(_text(tester), '1.000.000.000');
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'Enter sets total once, groups typing and updates all inventory modes',
    (tester) async {
      final h = PlannerTestHarness();
      addTearDown(h.controller.dispose);
      h.controller.active.commitInventory(_name, '100');
      var notifications = 0;
      h.controller.active.state.addListener(() => notifications++);
      await tester.pumpWidget(_host(h));
      await tester.tap(_amount);
      await tester.pump();
      expect(_text(tester), '100');
      await tester.enterText(find.byType(TextField), '25430');
      expect(_text(tester), '25.430');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('25.4k'), findsOneWidget);
      expect(notifications, 1);
      expect(
        h.controller.active.state.value.ignoreIngredientInventory,
        isFalse,
      );
      for (final mode in CraftMode.values) {
        expect(h.controller.modes[mode]!.state.value.inventory[_name], 25430);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(
        notifications,
        1,
        reason: 'Removing a committed row must not save twice.',
      );
    },
  );

  testWidgets('blur commits; pending removed-card drafts are not saved', (
    tester,
  ) async {
    final h = PlannerTestHarness();
    addTearDown(h.controller.dispose);
    await tester.pumpWidget(_host(h));
    await tester.tap(_amount);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '12500');
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    expect(h.controller.active.state.value.inventory[_name], 12500);
    expect(find.text('12.5k'), findsOneWidget);
    await tester.tap(_amount);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '30000');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(h.controller.active.state.value.inventory[_name], 12500);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid and paused edits preserve inventory; zero is valid', (
    tester,
  ) async {
    final h = PlannerTestHarness();
    addTearDown(h.controller.dispose);
    h.controller.active.commitInventory(_name, '50');
    await tester.pumpWidget(_host(h));
    await tester.tap(_amount);
    await tester.pump();
    for (final invalid in ['', '-5']) {
      await tester.enterText(find.byType(TextField), invalid);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(h.controller.active.state.value.inventory[_name], 50);
      expect(find.text('Use 0 or more'), findsOneWidget);
    }
    h.controller.freezeMutationsForRestart();
    await tester.enterText(find.byType(TextField), '20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(h.controller.active.state.value.inventory[_name], 50);
    expect(find.text('Edits are paused'), findsOneWidget);
    h.controller.resumeMutationsAfterRestartFailure();
    await tester.enterText(find.byType(TextField), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(h.controller.active.state.value.inventory[_name], isNull);
    expect(find.text('0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('${key.keyLabel} activates number; Escape discards edits', (
      tester,
    ) async {
      final h = PlannerTestHarness();
      addTearDown(h.controller.dispose);
      h.controller.active.commitInventory(_name, '25430');
      await tester.pumpWidget(_host(h));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(_text(tester), '25.430');
      await tester.enterText(find.byType(TextField), '88888');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('25.4k'), findsOneWidget);
      expect(h.controller.active.state.value.inventory[_name], 25430);
      expect(h.controller.active.state.value.ignoreIngredientInventory, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'shared updates refresh idle values but preserve a current draft',
    (tester) async {
      final h = PlannerTestHarness();
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(_host(h));
      h.controller.modes[CraftMode.cooking]!.commitInventory(_name, '1000000');
      await tester.pump();
      expect(find.text('1M'), findsOneWidget);
      await tester.tap(_amount);
      await tester.pump();
      expect(_text(tester), '1.000.000');
      await tester.enterText(find.byType(TextField), '12345');
      h.controller.modes[CraftMode.cooking]!.commitInventory(_name, '3000000');
      await tester.pump();
      expect(_text(tester), '12.345');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('3M'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('hover shows the full amount', (tester) async {
    final h = PlannerTestHarness();
    addTearDown(h.controller.dispose);
    h.controller.active.commitInventory(_name, '25430');
    await tester.pumpWidget(_host(h));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(_amount));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('25.430'), findsOneWidget);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recycling the editor for another item discards the old draft', (
    tester,
  ) async {
    final h = PlannerTestHarness();
    addTearDown(h.controller.dispose);
    h.controller.active.commitInventory(_name, '20');
    await tester.pumpWidget(_host(h));
    await tester.tap(_amount);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '999');
    await tester.pumpWidget(_host(h, itemName: 'Sunrise Herb'));
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(h.controller.active.state.value.inventory[_name], 20);
    expect(h.controller.active.state.value.inventory['Sunrise Herb'], isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final spec in [
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
    SakuraNightGardenSpec.theme,
  ]) {
    testWidgets(
      'active long icon footer keeps five recipe routes usable in ${spec.id}',
      (tester) async {
        final h = PlannerTestHarness(includeRecipeVariants: true);
        FlutterErrorDetails? lastError;
        final originalErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          lastError = details;
          originalErrorHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalErrorHandler);
        addTearDown(h.controller.dispose);
        final original = h.controller.catalog;
        const name = 'Clear Liquid Reagent';
        final base = original.alchemy.items[name]!;
        final controller = PlannerApplicationController(
          catalog: CatalogSnapshot(
            sourceSha256: original.sourceSha256,
            sourceByteCount: original.sourceByteCount,
            alchemy: ModeCatalog(
              mode: CraftMode.alchemy,
              items: {
                ...original.alchemy.items,
                name: Recipe(
                  name: name,
                  type: base.type,
                  baseOutput: base.baseOutput,
                  group: base.group,
                  method: base.method,
                  ingredients: base.ingredients,
                  marketId: base.marketId,
                  sourceNote: base.sourceNote,
                  vendor: base.vendor,
                  location: base.location,
                  npcPrice: base.npcPrice,
                  qualityBase: base.qualityBase,
                  qualityGrade: base.qualityGrade,
                  outputMinimum: 1,
                  outputMaximum: 1,
                  variants: [
                    for (var route = 0; route < 5; route++)
                      for (final batch in [1, 10, 100])
                        RecipeVariant(
                          id: 'route-$route-$batch',
                          routeId: 'route-$route',
                          label: 'Recipe route $route',
                          type: 'alchemy',
                          baseOutput: batch.toDouble(),
                          batchMultiplier: batch,
                          method: null,
                          ingredients: [
                            Ingredient(
                              name: 'Sunrise Herb',
                              quantity: batch.toDouble(),
                              options: const [],
                              substituteGroup: null,
                              substituteRatios: const {},
                            ),
                          ],
                          outputMinimum: batch.toDouble(),
                          outputMaximum: batch.toDouble(),
                        ),
                  ],
                  defaultVariantId: 'route-0-1',
                ),
              },
              iconDataUris: original.alchemy.iconDataUris,
              defaults: original.alchemy.defaults,
              metadata: original.alchemy.metadata,
              searchAliases: original.alchemy.searchAliases,
            ),
            cooking: original.cooking,
            processing: original.processing,
            supportingData: original.supportingData,
            collisions: original.collisions,
          ),
          initialState: h.controller.documentSnapshot,
          saveState: (state) async => state,
        );
        addTearDown(controller.dispose);
        for (final scale in [1.0, 1.5]) {
          for (final width in [1000.0, 1050.0, 1100.0]) {
            await setPlannerTestSize(tester, Size(width, 1200));
            await tester.pumpWidget(
              MaterialApp(
                theme: spec.materialTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ThemeSpecScope(
                  spec: spec,
                  child: Scaffold(
                    body: PlannerView(
                      controller: controller.active,
                      externalActions: h.actions,
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            final amount = find.byKey(
              const ValueKey('planner-inventory-amount-$name'),
            );
            await tester.ensureVisible(amount);
            await tester.tap(amount);
            await tester.pump();
            final editor = find.byKey(
              const ValueKey('planner-inventory-editor-$name'),
            );
            await tester.enterText(editor, '999999999999');
            await tester.pump();
            expect(
              tester.widget<TextField>(editor).controller!.text,
              '999.999.999.999',
            );
            expect(
              find.byKey(RecipeVariantSelector.routeChoiceKey(name, 'route-4')),
              findsOneWidget,
            );
            expect(
              find.byKey(RecipeVariantSelector.batchChoiceKey(name, 100)),
              findsOneWidget,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${spec.id}, $width wide, text scale $scale\n$lastError',
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpWidget(const SizedBox());
            expect(controller.active.state.value.inventory[name], isNull);
          }
        }
      },
    );
  }
}

const _name = 'Intermediate Reagent';
Finder get _amount =>
    find.byKey(const ValueKey('planner-inventory-amount-$_name'));
String _text(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Widget _host(
  PlannerTestHarness h, {
  ThemeSpec spec = StandardSpec.theme,
  double textScale = 1,
  String itemName = _name,
}) => MaterialApp(
  theme: spec.materialTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: ThemeSpecScope(
    spec: spec,
    child: Scaffold(
      body: Center(
        child: PlannerInventoryInput(
          controller: h.controller.active,
          itemName: itemName,
          iconBuilder: (size) => SizedBox.square(
            dimension: size,
            child: const ColoredBox(color: Colors.teal),
          ),
        ),
      ),
    ),
  ),
);
