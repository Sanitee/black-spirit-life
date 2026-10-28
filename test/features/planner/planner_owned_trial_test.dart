import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _target = 'HAN Reforge Stone - All AP';
const _capture = bool.fromEnvironment('CAPTURE_PLANNER_OWNED_TRIAL');
const _captureRoot = ValueKey('planner-owned-trial-capture-root');
const _themes = <ThemeSpec>[
  SakuraNightGardenSpec.theme,
  IlluminatedLedgerSpec.theme,
  StandardSpec.theme,
];

Finder _need(String name) => find.byKey(ValueKey('need:$name'));
Finder _amount(String name) =>
    find.byKey(ValueKey('planner-inventory-amount-$name'));
Finder _editor(String name) =>
    find.byKey(ValueKey('planner-inventory-editor-$name'));
Finder _craftQuantity(String name, String label) =>
    find.byKey(ValueKey('planner-craft-quantity:$name:$label'));

void main() {
  if (_capture) setUpAll(_loadCaptureFonts);

  for (final spec in _themes) {
    for (final size in const [Size(1200, 752), Size(1500, 940)]) {
      testWidgets(
        'Completed disclosure includes covered crafts and stays collapsed in ${spec.id} $size',
        (tester) async {
          configureApplicationTestSurface(tester, size);
          final harness = await _createHarness(tester, spec);
          try {
            final mode = harness.bundle.controller.active;
            mode.commitQueueInventory('Caphras Stone', '10000');
            await _mount(tester, harness);
            final button = find.byKey(
              const ValueKey('planner-completed-disclosure'),
            );
            final completed = find.byKey(
              const ValueKey('planner-completed-step:Caphras Stone'),
            );
            expect(button, findsOneWidget);
            expect(find.text('Completed 1'), findsOneWidget);
            expect(completed, findsNothing);
            expect(mode.state.value.completedSteps, isEmpty);
            final ownedBefore = harness.bundle.controller.documentSnapshot;
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(completed, findsOneWidget);
            expect(
              harness.bundle.controller.documentSnapshot,
              same(ownedBefore),
            );
            mode.commitQueueInventory('Caphras Stone', '0');
            await tester.pumpAndSettle();
            await _complete(tester, 'Caphras Stone');
            await _resetLists(tester);
            expect(button, findsOneWidget);
            expect(find.text('Completed 1'), findsOneWidget);
            expect(
              completed,
              findsNothing,
              reason: 'New completion auto-hides.',
            );
            await tester.tap(button);
            await tester.pumpAndSettle();
            _expectInlineQueueActions(tester, button);
            // Inherit the button foreground, including Ledger's light-on-blue.
            expect(
              tester.widget<Text>(find.text('Completed 1')).style?.color,
              isNull,
            );
            expect(completed, findsOneWidget);
            expect(
              find.descendant(
                of: completed,
                matching: _amount('Caphras Stone'),
              ),
              findsNothing,
            );
            expect(find.textContaining('needed · Owned'), findsNothing);
            expect(
              find.byKey(
                const ValueKey('planner-completed-preview:Caphras Stone'),
              ),
              findsOneWidget,
            );
            await _captureIfRequested(
              tester,
              'completed-expanded-${spec.id}-${size.width.toInt()}',
            );
            final before = harness.bundle.controller.documentSnapshot;
            final planBefore = mode.plan.value;
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(completed, findsNothing);
            expect(mode.plan.value, same(planBefore));
            expect(harness.bundle.controller.documentSnapshot, same(before));
            expect(
              find.byKey(PlannerActionKeys.row('P08', _target)),
              findsOneWidget,
            );
            await _captureIfRequested(
              tester,
              'completed-collapsed-${spec.id}-${size.width.toInt()}',
            );

            // Covered crafts count too, but unrelated/raw stock never does.
            mode.commitQueueInventory('Magical Shard', '450');
            await tester.pumpAndSettle();
            expect(find.text('Completed 2'), findsOneWidget);
            mode.commitQueueInventory('Black Stone', '10000');
            await tester.pumpAndSettle();
            expect(find.text('Completed 2'), findsOneWidget);
            expect(completed, findsNothing);
            mode.commitQueueInventory('Magical Shard', '0');
            await tester.pumpAndSettle();
            await _complete(tester, 'Magical Shard');
            expect(find.text('Completed 2'), findsOneWidget);
            expect(completed, findsNothing);
            await tester.tap(button);
            await tester.pumpAndSettle();
            await _resetLists(tester);
            expect(completed, findsOneWidget);
            expect(
              find.byKey(
                const ValueKey('planner-completed-step:Magical Shard'),
              ),
              findsOneWidget,
            );
            await tester.tap(
              find.byKey(const ValueKey('planner-undo-completion')),
            );
            await tester.pumpAndSettle();
            expect(find.text('Completed 1'), findsOneWidget);
            expect(
              find.byKey(
                const ValueKey('planner-completed-step:Magical Shard'),
              ),
              findsNothing,
            );
            final inventoryBeforeRestart = Map<String, double>.of(
              mode.state.value.inventory,
            );
            await tester.tap(find.byKey(PlannerActionKeys.p07));
            await tester.pumpAndSettle();
            expect(mode.state.value.completedSteps, isEmpty);
            expect(mode.state.value.inventory, inventoryBeforeRestart);
            expect(find.text('Completed 1'), findsOneWidget);
            expect(completed, findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            await _dispose(tester, harness);
          }
        },
      );
    }

    testWidgets(
      'Completed steps remain after their outputs are consumed in ${spec.id}',
      (tester) async {
        configureApplicationTestSurface(tester, const Size(1500, 940));
        final harness = await _createHarness(tester, spec);
        try {
          final mode = harness.bundle.controller.active;
          const names = [
            'Caphras Stone',
            'Magical Shard',
            'Black Stone Powder',
            'Pure Powder Reagent',
          ];
          // A bounded test formula exercises four sequentially completed outputs.
          mode.updateState(
            (state) => state.copyWith(
              recipeEdits: {
                _target: RecipeState(
                  type: 'processing',
                  baseOutput: 1,
                  outputMinimum: 1,
                  outputMaximum: 1,
                  ingredients: [
                    for (final name in names)
                      IngredientState(name: name, quantity: 1),
                  ],
                ),
                for (final name in names)
                  name: RecipeState(
                    type: 'simple_alchemy',
                    baseOutput: 1,
                    ingredients: [
                      IngredientState(name: 'Black Stone', quantity: 1),
                    ],
                  ),
              },
            ),
          );
          await _mount(tester, harness);
          for (final name in names) {
            await _complete(tester, name);
          }
          await _resetLists(tester);
          expect(mode.state.value.completedSteps.toList(), names);
          const codec = PlannerStateJsonCodec();
          final restoredState = codec.decode(
            codec.encode(harness.bundle.controller.documentSnapshot),
          );
          expect(restoredState.processing.completedSteps.toList(), names);
          final button = find.byKey(
            const ValueKey('planner-completed-disclosure'),
          );
          expect(find.text('Completed 4'), findsOneWidget);
          _expectInlineQueueActions(tester, button);
          final previews = find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'planner-completed-preview:',
                ),
          );
          expect(previews, findsNWidgets(3));
          await _captureIfRequested(tester, 'completed-four-inline-${spec.id}');
          for (final name in names) {
            expect(
              find.byKey(ValueKey('planner-completed-step:$name')),
              findsNothing,
            );
          }
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('planner-completed-step:Caphras Stone')),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('planner-completed-step:Caphras Stone')),
            findsNothing,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('planner-completed-step:Caphras Stone')),
            findsOneWidget,
          );
          await _complete(tester, _target);
          await _resetLists(tester);
          expect(find.text('Completed 5'), findsOneWidget);
          expect(mode.state.value.completedSteps.toList(), [...names, _target]);
          expect(
            find.byKey(const ValueKey('planner-completed-step:Caphras Stone')),
            findsNothing,
          );
          await tester.tap(button);
          await tester.pumpAndSettle();
          for (final name in names) {
            expect(mode.state.value.inventory[name] ?? 0, 0);
            expect(
              find.byKey(ValueKey('planner-completed-step:$name')),
              findsOneWidget,
            );
          }
          await _captureIfRequested(tester, 'completed-consumed-${spec.id}');
          await tester.tap(button);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('planner-undo-completion')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Completed 4'), findsOneWidget);
          expect(mode.state.value.completedSteps.toList(), names);
          expect(
            find.byKey(const ValueKey('planner-completed-step:Caphras Stone')),
            findsNothing,
          );
          mode.selectTarget('Black Gem');
          await tester.pumpAndSettle();
          expect(mode.state.value.completedSteps, isEmpty);
          expect(button, findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, harness);
        }
      },
    );

    testWidgets(
      'completion Undo remains readable and restores the card in ${spec.id}',
      (tester) async {
        configureApplicationTestSurface(tester, const Size(1200, 752));
        final harness = await _createHarness(tester, spec);
        try {
          await _mount(tester, harness);
          final mode = harness.bundle.controller.active;
          final inventoryBefore = Map<String, double>.of(
            mode.state.value.inventory,
          );
          final step = mode.plan.value.steps.first;
          final complete = find.byKey(PlannerActionKeys.row('P08', step.name));
          await _showInList(tester, complete, queue: true);
          await tester.tap(complete);
          await tester.pumpAndSettle();
          final undo = find.byKey(
            const ValueKey<String>('planner-undo-completion'),
          );
          expect(undo, findsOneWidget);
          expect(mode.state.value.inventory[step.name], step.produced);
          await _captureIfRequested(tester, 'completion-undo-${spec.id}');
          await tester.tap(undo);
          await tester.pumpAndSettle();
          expect(mode.state.value.inventory, inventoryBefore);
          expect(
            find.byKey(PlannerActionKeys.row('P08', step.name)),
            findsOneWidget,
          );
          expect(undo, findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, harness);
        }
      },
    );
    for (final size in const [Size(1200, 752), Size(1500, 940)]) {
      testWidgets(
        'owned trial real catalog ${spec.id} $size keeps queue and market states clear',
        (tester) async {
          configureApplicationTestSurface(tester, size);
          final harness = await _createHarness(tester, spec);
          try {
            await _mount(tester, harness);
            final mode = harness.bundle.controller.active;
            final plan = mode.plan.value;
            expect(plan.target, _target);
            expect(plan.want, 3);
            expect(
              plan.steps.map((step) => step.name),
              contains('Caphras Stone'),
            );

            for (final step in plan.steps) {
              await _showInList(
                tester,
                find.byKey(ValueKey('planner-queue-icon:${step.name}')),
                queue: true,
              );
              _expectQueueGeometryAndQuantities(tester, step);
            }
            for (final name in [
              'Ancient Spirit Dust',
              'Magical Lightstone Crystal',
            ]) {
              await _showInList(tester, _need(name));
              _expectAvailableNonMarketRow(tester, name, spec);
            }
            for (final name in ["Nev's Fragment", 'Reforge Stone - All AP']) {
              await _showInList(tester, _need(name));
              expect(
                find.descendant(
                  of: _need(name),
                  matching: find.text('Out of stock'),
                ),
                findsOneWidget,
              );
              expect(
                find.descendant(
                  of: _need(name),
                  matching: find.byKey(ValueKey('planner-market-accent:$name')),
                ),
                findsOneWidget,
              );
            }

            // Confirmed unlisted receipts must stay just as quiet after reload.
            mode.updateState(
              (state) => state.copyWith(
                market: state.market.copyWith(
                  // Stale stock data must not colour a non-market item amber.
                  stock: {
                    ...state.market.stock,
                    'Ancient Spirit Dust': 0,
                    'Magical Lightstone Crystal': 0,
                  },
                  unlistedItemNames: const [
                    'Ancient Spirit Dust',
                    'Magical Lightstone Crystal',
                  ],
                ),
              ),
              immediate: true,
            );
            await tester.pumpAndSettle();
            await _resetLists(tester);
            for (final name in [
              'Ancient Spirit Dust',
              'Magical Lightstone Crystal',
            ]) {
              await _showInList(tester, _need(name));
              _expectAvailableNonMarketRow(tester, name, spec);
            }
            await _resetLists(tester);
            expect(find.byType(Scrollbar), findsNothing);
            expect(find.byType(RawScrollbar), findsNothing);
            expect(tester.takeException(), isNull);
            await _captureIfRequested(
              tester,
              '${spec.id}-${size.width.toInt()}x${size.height.toInt()}',
            );
          } finally {
            await _dispose(tester, harness);
          }
        },
      );
    }
  }

  testWidgets(
    'real Caphras inventory edit recalculates without adding a completed mark',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester, SakuraNightGardenSpec.theme);
      try {
        await _mount(tester, harness);
        final application = harness.bundle.controller;
        final mode = application.active;
        final before = mode.plan.value;
        final initialCaphras = before.steps.singleWhere(
          (step) => step.name == 'Caphras Stone',
        );
        expect(initialCaphras.demand, 300);
        expect(mode.state.value.ignoreIngredientInventory, isTrue);
        final crystalNeed = before.missing.singleWhere(
          (row) => row.name == 'Magical Lightstone Crystal',
        );

        await _setInventory(tester, 'Caphras Stone', '100');
        expect(mode.state.value.ignoreIngredientInventory, isFalse);
        for (final craftMode in CraftMode.values) {
          expect(
            application.documentSnapshot
                .forMode(craftMode)
                .inventory['Caphras Stone'],
            100,
          );
        }
        final partial = mode.plan.value;
        final caphras = partial.steps.singleWhere(
          (step) => step.name == 'Caphras Stone',
        );
        expect(caphras.count, 200);
        expect(caphras.produced, 200);
        expect(caphras.demand, 300);
        expect(
          partial.missing
              .singleWhere((row) => row.name == 'Ancient Spirit Dust')
              .missing,
          1000,
        );
        expect(
          partial.missing
              .singleWhere((row) => row.name == 'Black Stone')
              .missing,
          200,
        );
        expect(
          partial.missing
              .singleWhere((row) => row.name == crystalNeed.name)
              .missing,
          crystalNeed.missing,
        );
        _expectQueueGeometryAndQuantities(tester, caphras);
        await _resetLists(tester);
        await _captureIfRequested(tester, 'sakura-partial-caphras-100');

        await _setInventory(tester, 'Caphras Stone', '300');
        expect(
          mode.plan.value.steps.map((step) => step.name),
          isNot(contains('Caphras Stone')),
        );
        expect(
          mode.plan.value.missing.map((row) => row.name),
          isNot(contains('Ancient Spirit Dust')),
        );
        expect(
          find.byKey(const ValueKey('planner-completed-disclosure')),
          findsOneWidget,
        );
        expect(mode.state.value.completedSteps, isEmpty);
        await _resetLists(tester);
        await _captureIfRequested(tester, 'sakura-covered-caphras-300');

        // Inventory corrections still restore work, without becoming completion history.
        mode.commitQueueInventory('Caphras Stone', '0');
        await tester.pumpAndSettle();
        expect(mode.state.value.inventory['Caphras Stone'], isNull);
        expect(
          mode.plan.value.steps
              .singleWhere((step) => step.name == 'Caphras Stone')
              .count,
          300,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, harness);
      }
    },
  );
}

void _expectInlineQueueActions(WidgetTester tester, Finder owned) {
  final bounds = find.byKey(const ValueKey('planner-queue-header'));
  final header = find.descendant(
    of: bounds,
    matching: find.byType(SectionHeader),
  );
  expect(header, findsOneWidget);
  expect(tester.widget<SectionHeader>(header).meta, isNull);
  final title = find.descendant(
    of: header,
    matching: find.byKey(SectionHeader.titleKey),
  );
  final titleRect = tester.getRect(title);
  final ownedRect = tester.getRect(owned);
  final restartRect = tester.getRect(find.byKey(PlannerActionKeys.p07));
  final headerRect = tester.getRect(bounds);
  for (final action in [ownedRect, restartRect]) {
    expect(action.left, greaterThanOrEqualTo(headerRect.left));
    expect(action.right, lessThanOrEqualTo(headerRect.right));
    expect(action.bottom, lessThanOrEqualTo(headerRect.bottom));
  }
  if (ownedRect.top >= titleRect.bottom) {
    expect(restartRect.top, greaterThanOrEqualTo(titleRect.bottom));
  } else {
    expect(ownedRect.center.dy, closeTo(titleRect.center.dy, 8));
    expect(restartRect.center.dy, closeTo(titleRect.center.dy, 8));
    expect(titleRect.right, lessThanOrEqualTo(ownedRect.left));
    expect(ownedRect.right, lessThan(restartRect.left));
  }
  expect(find.textContaining(RegExp(r'^\d+ left$')), findsNothing);
  if (_capture && tester.widget<Text>(title).data == 'Craft Queue') {
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
      reason: 'The decorative rule must not displace the real heading.',
    );
  }
}

Future<ApplicationTestHarness> _createHarness(
  WidgetTester tester,
  ThemeSpec spec,
) async {
  final original = (await tester.runAsync(
    () => ApplicationTestHarness.create(
      backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
      activeMode: CraftMode.processing,
    ),
  ))!;
  final harness = original.rebindControllerInCurrentZone();
  await tester.runAsync(original.disposeControllerOnly);
  final mode = harness.bundle.controller.active;
  mode.selectTarget(_target);
  mode.commitAmount('3');
  for (final name in ['Caphras Stone', 'Magical Shard']) {
    if (mode.optionalProcessingRecipe(name) != null) {
      expect(mode.selectProcessingAcquisition(name, process: true), isTrue);
    }
  }
  mode.selectRecipeVariant(recipeName: 'Caphras Stone', variantId: 'standard');
  mode.updateState(
    (state) => state.copyWith(
      inventory: {},
      ignoreTargetInventory: true,
      ignoreIngredientInventory: true,
      useMassProcessing: false,
      market: state.market.copyWith(
        prices: const {
          'Black Stone': 129000,
          'Sealed Black Magic Crystal': 4500000,
          "Nev's Fragment": 46600000,
          'Reforge Stone - All AP': 935000000,
          // Stale values must not make nonregisterable items look tradable.
          'Ancient Spirit Dust': 999,
          'Magical Lightstone Crystal': 999,
        },
        stock: const {
          'Black Stone': 45893,
          'Sealed Black Magic Crystal': 9572,
          "Nev's Fragment": 0,
          'Reforge Stone - All AP': 0,
          'Ancient Spirit Dust': 0,
          'Magical Lightstone Crystal': 0,
        },
        unlistedItemNames: const [],
        fetchedAt: DateTime.utc(2026, 9, 21, 12).millisecondsSinceEpoch,
        region: 'eu',
      ),
    ),
    immediate: true,
  );
  mode.setPricesVisible(true);
  return harness;
}

Future<void> _mount(WidgetTester tester, ApplicationTestHarness harness) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureRoot,
      child: BdoCraftPlannerApp(
        enableOpportunityAutoCheck: false,
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _dispose(
  WidgetTester tester,
  ApplicationTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await harness.disposeControllerOnly();
  await tester.runAsync(
    () => harness.temporaryDirectory.delete(recursive: true),
  );
}

Future<void> _showInList(
  WidgetTester tester,
  Finder target, {
  bool queue = false,
}) async {
  final list = find.byKey(
    PageStorageKey<String>(
      queue ? 'planner-craft-queue' : 'planner-need-first',
    ),
  );
  // Need First also contains horizontally scrollable amount fields.
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(target, 160, scrollable: scrollable);
  await tester.pumpAndSettle();
}

Future<void> _resetLists(WidgetTester tester) async {
  for (final key in ['planner-craft-queue', 'planner-need-first']) {
    final list = find.byKey(PageStorageKey<String>(key));
    if (list.evaluate().isEmpty) continue;
    final controller = tester.widget<ListView>(list).controller;
    if (controller != null && controller.hasClients) controller.jumpTo(0);
  }
  await tester.pumpAndSettle();
}

void _expectQueueGeometryAndQuantities(WidgetTester tester, PlanStep step) {
  final icon = find.byKey(ValueKey('planner-queue-icon:${step.name}'));
  final title = find.byKey(PlannerActionKeys.row('P10', step.name));
  final amount = _amount(step.name);
  expect(icon, findsOneWidget);
  expect(title, findsOneWidget);
  expect(amount, findsOneWidget);
  final iconBounds = tester.getRect(icon);
  final titleBounds = tester.getRect(title);
  expect(
    (titleBounds.top - iconBounds.top).abs(),
    lessThanOrEqualTo(4),
    reason: '${step.name}: title starts alongside the top of its item icon',
  );
  final footer = tester.getRect(
    find.byKey(ValueKey('planner-inventory-footer-${step.name}')),
  );
  expect(footer.top, closeTo(iconBounds.bottom, .1));
  expect(footer.left, closeTo(iconBounds.left, .1));
  expect(footer.width, closeTo(iconBounds.width, .1));
  expect(tester.getRect(amount).top, greaterThanOrEqualTo(iconBounds.bottom));
  for (final entry in {
    'Craft': step.count,
    'Results': step.produced,
    'Need': step.demand,
  }.entries) {
    expect(
      tester.widget<Text>(_craftQuantity(step.name, entry.key)).data,
      formatQuantity(entry.value),
    );
  }
  final header = tester.getRect(
    find.byKey(ValueKey('planner-queue-heading:${step.name}')),
  );
  final fields = [
    for (final label in ['Craft', 'Results', 'Need'])
      tester.getRect(
        find.byKey(ValueKey('planner-craft-field:${step.name}:$label')),
      ),
  ];
  for (var index = 0; index < fields.length; index++) {
    final field = fields[index];
    expect(field.left, greaterThanOrEqualTo(header.left));
    expect(field.right, lessThanOrEqualTo(header.right));
    expect(field.top, greaterThanOrEqualTo(titleBounds.bottom));
    expect(field.bottom, lessThanOrEqualTo(header.bottom));
    if (index == 0) continue;
    final previous = fields[index - 1];
    if (field.top >= previous.bottom) {
      // A compact header wraps whole quantity groups on narrow layouts.
      expect(field.top - previous.bottom, greaterThanOrEqualTo(5.9));
    } else {
      expect(field.left - previous.right, greaterThanOrEqualTo(19.9));
    }
  }
}

void _expectAvailableNonMarketRow(
  WidgetTester tester,
  String name,
  ThemeSpec spec,
) {
  final row = _need(name);
  expect(row, findsOneWidget);
  final surface = tester.widget<AppSurface>(
    find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) => widget is AppSurface && widget.role == AppSurfaceRole.row,
      ),
    ),
  );
  expect(surface.tone, AppSurfaceTone.success);
  expect(
    find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(
              r'(^Stock\b|Out of stock|each$|^Total\b|^No price$|Central Market|No market update)',
            ).hasMatch(widget.data ?? ''),
      ),
    ),
    findsNothing,
  );
  final edge = find.byKey(ValueKey('planner-market-accent:$name'));
  expect(edge, findsOneWidget);
  expect(
    (tester.widget<DecoratedBox>(edge).decoration as BoxDecoration).color,
    spec.plannerAvailableAccent,
  );
  for (final label in ['Need', 'Have', 'Missing']) {
    expect(
      find.descendant(of: row, matching: find.text(label)),
      findsOneWidget,
    );
  }
}

Future<void> _setInventory(
  WidgetTester tester,
  String name,
  String quantity,
) async {
  await tester.ensureVisible(_amount(name));
  await tester.tap(_amount(name));
  await tester.pumpAndSettle();
  expect(_editor(name), findsOneWidget);
  await tester.enterText(_editor(name), quantity);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Future<void> _complete(WidgetTester tester, String name) async {
  await _resetLists(tester);
  final button = find.byKey(PlannerActionKeys.row('P08', name));
  await _showInList(tester, button, queue: true);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _captureIfRequested(WidgetTester tester, String name) async {
  if (!_capture) return;
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureRoot),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      const directory = String.fromEnvironment(
        'PLANNER_OWNED_TRIAL_CAPTURE_DIRECTORY',
        defaultValue: 'tmp/planner-owned-trial',
      );
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}

Future<void> _loadCaptureFonts() async {
  final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (flutterRoot.parent.path == flutterRoot.path) {
      throw StateError('Flutter font directory not found.');
    }
    flutterRoot = flutterRoot.parent;
  }
  final materialFonts =
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts';
  for (final entry in {
    'Segoe UI': [
      '$windowsRoot/Fonts/segoeui.ttf',
      '$windowsRoot/Fonts/seguisb.ttf',
      '$windowsRoot/Fonts/segoeuib.ttf',
    ],
    'Georgia': [
      '$windowsRoot/Fonts/georgia.ttf',
      '$windowsRoot/Fonts/georgiab.ttf',
      '$windowsRoot/Fonts/georgiai.ttf',
    ],
    'Roboto': [
      '$materialFonts/roboto-regular.ttf',
      '$materialFonts/roboto-bold.ttf',
    ],
    'MaterialIcons': ['$materialFonts/materialicons-regular.otf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
