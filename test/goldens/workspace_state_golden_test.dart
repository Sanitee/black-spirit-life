import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_copy_toast.dart';
import 'package:bdo_craft_planner_flutter/data/portable/portable_v4_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/data/data.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_form_controls.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_vector_glyph.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

typedef _Family = ({String name, String? background});

void main() {
  const goldenRoot = ValueKey<String>('state-golden-workspace-root');
  const states = <String>[
    'recipe_book',
    'substitute_popover',
    'source_popover',
    'copy_toast',
    'data_profile',
    'inventory_category_menu',
    'titlebar_tooltip',
    'keyboard_focus',
  ];
  const families = <_Family>[
    (name: 'standard', background: null),
    (name: 'ledger', background: IlluminatedLedgerSpec.backgroundId),
    (name: 'sakura', background: SakuraNightGardenSpec.backgroundId),
  ];
  const sizes = <Size>[Size(1200, 752), Size(1500, 940)];

  for (final family in families) {
    for (final state in states) {
      for (final size in sizes) {
        testWidgets(
          '${family.name} $state ${size.width}x${size.height} state baseline',
          (tester) async {
            configureApplicationTestSurface(tester, size);
            final platformMessenger = TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger;
            platformMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              (_) async => null,
            );
            addTearDown(
              () => platformMessenger.setMockMethodCallHandler(
                SystemChannels.platform,
                null,
              ),
            );
            final harness = (await tester.runAsync(
              () => ApplicationTestHarness.create(
                backgroundId: family.background ?? 'greenhouse',
                activeMode: CraftMode.alchemy,
                view: _initialView(state),
              ),
            ))!;
            try {
              await tester.pumpWidget(
                RepaintBoundary(
                  key: goldenRoot,
                  child: BdoCraftPlannerApp(
                    applicationFuture: Future.value(harness.bundle),
                    marketGateway: const EmptyMarketGateway(),
                  ),
                ),
              );
              await _pumpFrames(tester);
              await _prepareState(
                tester,
                harness,
                state,
                familyName: family.name,
              );
              // Named theme images always receive a decode window. The focused
              // inventory-menu baseline needs the same treatment for the
              // standard greenhouse fallback so it matches its full-suite frame.
              if (family.background == IlluminatedLedgerSpec.backgroundId ||
                  family.background == SakuraNightGardenSpec.backgroundId ||
                  (family.background == null &&
                      (state == 'inventory_category_menu' ||
                          state.startsWith('data_')))) {
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 160)),
                );
                await _pumpFrames(tester);
              }
              expect(tester.takeException(), isNull);
              await expectLater(
                find.byKey(goldenRoot),
                matchesGoldenFile(
                  'states/state_${family.name}_${state}_${size.width.toInt()}x${size.height.toInt()}.png',
                ),
              );
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await tester.runAsync(harness.dispose);
            }
          },
        );
      }
    }
  }
}

String _initialView(String state) => switch (state) {
  'data_profile' || 'data_import_preview' || 'data_validation_error' => 'data',
  'inventory_category_menu' => 'inventory',
  _ => 'plan',
};

Future<void> _prepareState(
  WidgetTester tester,
  ApplicationTestHarness harness,
  String state, {
  required String familyName,
}) async {
  switch (state) {
    case 'recipe_book':
      await tester.tap(find.byKey(PlannerActionKeys.p03));
      await _pumpFrames(tester);
      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
      break;
    case 'substitute_popover':
      final mode = harness.bundle.controller.active;
      final candidate = mode.recipes.entries.firstWhere(
        (entry) =>
            entry.value.isCraftable &&
            entry.value.ingredients.any(
              (ingredient) => ingredient.options.length > 1,
            ),
      );
      expect(mode.selectTarget(candidate.key), isTrue);
      await _pumpFrames(tester);
      final swap = find.byWidgetPredicate(
        (widget) => widget is AppVectorGlyph && widget.name == 'swap',
      );
      if (swap.evaluate().isEmpty) {
        mode.toggleIngredients(candidate.key);
        await _pumpFrames(tester);
      }
      await tester.tap(swap.first);
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        find.bySemanticsLabel(RegExp(r'^Substitute choices for ')),
        findsOneWidget,
      );
      break;
    case 'source_popover':
      final mode = harness.bundle.controller.active;
      mode.updateState((state) {
        final metadata = Map<String, IngredientMetadata>.of(
          state.ingredientMeta,
        );
        metadata['Sunrise Herb'] =
            (metadata['Sunrise Herb'] ?? IngredientMetadata()).copyWith(
              sourceNote: 'Gathered near Heidel roads.',
            );
        return state.copyWith(ingredientMeta: metadata);
      }, immediate: true);
      expect(mode.selectTarget('Harmony Draught - Edania'), isTrue);
      await _pumpFrames(tester);
      final sourceAction = find.byKey(
        PlannerActionKeys.row('P17', 'Sunrise Herb'),
      );
      await _scrollViewUntilVisible(
        tester,
        sourceAction,
        const PageStorageKey<String>('planner-need-first'),
        delta: 180,
      );
      await tester.tap(sourceAction);
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        find.bySemanticsLabel('Source information for Sunrise Herb'),
        findsWidgets,
      );
      break;
    case 'copy_toast':
      final stepName =
          harness.bundle.controller.active.plan.value.steps.first.name;
      await tester.tap(find.byKey(PlannerActionKeys.row('P10', stepName)));
      await _pumpUntil(
        tester,
        () =>
            find.byKey(ApplicationCopyToastKeys.overlay).evaluate().isNotEmpty,
      );
      final toast = find.byKey(ApplicationCopyToastKeys.overlay);
      expect(toast, findsOneWidget);
      expect(toast.hitTestable(), findsNothing);
      expect(
        find.descendant(of: toast, matching: find.text('Copied $stepName')),
        findsOneWidget,
      );
      break;
    case 'data_import_preview':
      // Retain the historical golden identifier until the intentionally
      // changed baseline images are regenerated. The live parity state is now
      // the silent, completed import rather than a confirmation preview.
      await _showJsonEditor(tester);
      final portable = const PortableV4Codec().export(
        harness.bundle.controller.documentSnapshot,
        scopes: const PortableScopes.all(),
      );
      await tester.enterText(_jsonField(), portable);
      final importButton = tester.widget<AppButton>(
        find.byKey(const ValueKey<String>('D10')),
      );
      await importButton.onPressedAsync!();
      await _pumpFrames(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('data-operation-status')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('D10:undo')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      break;
    case 'data_validation_error':
      await _showJsonEditor(tester);
      await tester.enterText(_jsonField(), '{invalid portable json');
      final importButton = tester.widget<AppButton>(
        find.byKey(const ValueKey<String>('D10')),
      );
      await importButton.onPressedAsync!();
      await tester.pump();
      await _scrollDataUntilVisible(
        tester,
        find.textContaining('Import failed; no state changed'),
      );
      break;
    case 'inventory_category_menu':
      await harness.bundle.controller.updateDocumentDurably(
        (document) => document.copyWith(
          showDeleteTools: true,
          alchemy: document.alchemy.copyWith(
            inventory: <String, double>{
              ...document.alchemy.inventory,
              'Ash Sap': 1,
            },
          ),
        ),
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(InventoryActionKeys.i04));
      await _pumpFrames(tester);
      final editItems = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('I11:');
      });
      expect(editItems, findsWidgets);
      await tester.tap(editItems.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      final itemDialog = find.byType(Dialog);
      expect(itemDialog, findsOneWidget);
      final anchor = find.descendant(
        of: itemDialog,
        matching: find.byKey(AppSelect.anchorMaterialKey),
      );
      await tester.tap(anchor);
      // Pump once to install MenuAnchor's overlay, then advance its transition.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MenuItemButton).hitTestable(), findsWidgets);
      break;
    case 'titlebar_tooltip':
      final close = find.bySemanticsLabel('Close');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(close));
      await tester.pump(const Duration(milliseconds: 680));
      // The wait timer inserts the overlay at the end of the first pump; a
      // second pump is required for the tooltip's fade to become visible.
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.text('Close'), findsOneWidget);
      final tooltipRect = tester.getRect(find.text('Close'));
      expect(tooltipRect.width, greaterThan(0));
      expect(tooltipRect.height, greaterThan(0));
      expect(tooltipRect.top, greaterThanOrEqualTo(0));
      expect(
        tooltipRect.bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height),
      );
      addTearDown(mouse.removePointer);
      break;
    case 'keyboard_focus':
      final action = find.byKey(PlannerActionKeys.p03);
      final focusableFinder = find
          .descendant(
            of: action,
            matching: find.byType(FocusableActionDetector),
          )
          .first;
      final focusable = tester.widget<FocusableActionDetector>(focusableFinder);
      // Establish keyboard input modality, then put focus on a known retained
      // control so the baseline has a deterministic, inspectable focus ring.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      focusable.focusNode!.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(focusable.focusNode!.hasPrimaryFocus, isTrue);
      final material = tester.widget<AnimatedContainer>(
        find
            .descendant(of: action, matching: find.byKey(AppButton.materialKey))
            .first,
      );
      final decoration = material.decoration! as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.width, familyName == 'sakura' ? 2 : 1);
      break;
  }
}

Finder _jsonField() => find.descendant(
  of: find.byKey(const ValueKey<String>('D09')),
  matching: find.byType(TextField),
);

Future<void> _showJsonEditor(WidgetTester tester) async {
  if (find.byKey(const ValueKey<String>('D08')).evaluate().isEmpty) {
    final build = find.byKey(
      const ValueKey<String>('data-editor-unlock-build'),
    );
    await _scrollViewUntilVisible(
      tester,
      build,
      const ValueKey<String>('data-scroll'),
      delta: 300,
    );
    for (var tap = 0; tap < DataSessionController.editorUnlockTapCount; tap++) {
      await tester.tap(build);
    }
    await tester.pump(const Duration(milliseconds: 120));
  }
  final showJson = find.byKey(const ValueKey<String>('D08'));
  await _scrollViewUntilVisible(
    tester,
    showJson,
    const ValueKey<String>('data-scroll'),
    delta: 300,
  );
  await tester.tap(showJson);
  await tester.pump(const Duration(milliseconds: 120));
  await _scrollViewUntilVisible(
    tester,
    _jsonField(),
    const ValueKey<String>('data-scroll'),
    delta: 300,
  );
}

Future<void> _scrollDataUntilVisible(WidgetTester tester, Finder target) =>
    _scrollViewUntilVisible(
      tester,
      target,
      const ValueKey<String>('data-scroll'),
      delta: 300,
    );

Future<void> _scrollViewUntilVisible(
  WidgetTester tester,
  Finder target,
  Key scrollViewKey, {
  required double delta,
}) async {
  if (target.evaluate().isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pump();
    return;
  }
  final keyed = find.byKey(scrollViewKey);
  expect(keyed, findsOneWidget);
  final scrollView = tester.widget<ScrollView>(keyed);
  final controller = scrollView.controller;
  expect(controller, isNotNull);
  expect(controller!.hasClients, isTrue);
  for (var attempt = 0; attempt < 50 && target.evaluate().isEmpty; attempt++) {
    final position = controller.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) {
      break;
    }
    controller.jumpTo(next);
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
