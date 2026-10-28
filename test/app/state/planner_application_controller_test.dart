import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/first_run_setup.dart';
import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_appearance_theme.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_map_core/bdo_map_core.dart'
    show
        BdoGatherChecklist,
        BdoGatherChecklistEntry,
        BdoGatherChecklistSourceKind,
        BdoMapVisualStyle,
        BdoNodeNetworkPreferences,
        BdoTownWorkerCapacity,
        ResourceMapInterfaceStyle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Planner content size', () {
    test(
      'live preview and commit leave plans, modes and themes untouched',
      () async {
        final saves = <PlannerState>[];
        final controller = PlannerApplicationController(
          catalog: _catalog(),
          initialState: _document(),
          saveState: (state) async {
            saves.add(state);
            return state;
          },
          saveDebounce: Duration.zero,
        );
        final theme = ApplicationAppearanceThemeController(controller);
        final initial = controller.documentSnapshot;
        final plans = {
          for (final entry in controller.modes.entries)
            entry.key: entry.value.plan.value,
        };
        var modeNotifications = 0;
        var planNotifications = 0;
        var themeNotifications = 0;
        var sizeNotifications = 0;
        for (final mode in controller.modes.values) {
          mode.state.addListener(() => modeNotifications++);
          mode.plan.addListener(() => planNotifications++);
        }
        theme.addListener(() => themeNotifications++);
        controller.plannerContentScale.addListener(() => sizeNotifications++);
        for (var i = 1; i <= 200; i++) {
          controller.previewPlannerContentScale(1 + i / 1000);
        }
        await controller.flush();
        expect(controller.plannerContentScale.value, 1.2);
        expect(sizeNotifications, 200);
        expect(controller.documentSnapshot, same(initial));
        expect(saves, isEmpty);
        controller.commitPlannerContentScale();
        await controller.flush();
        expect(saves, hasLength(1));
        expect(saves.single.plannerContentScale, 1.2);
        expect(modeNotifications, 0);
        expect(planNotifications, 0);
        expect(themeNotifications, 0);
        for (final entry in controller.modes.entries) {
          expect(entry.value.state.value, same(initial.forMode(entry.key)));
          expect(entry.value.plan.value, same(plans[entry.key]));
        }
        controller.commitPlannerContentScale();
        controller.commitPlannerContentScale(1);
        controller.commitPlannerContentScale(1);
        await controller.flush();
        expect(saves, hasLength(2));
        expect(saves.last.plannerContentScale, 1);
        expect(controller.plannerContentScale.value, 1);
        theme.dispose();
        await controller.dispose();
      },
    );

    test(
      'unrelated autosaves and mode switches never persist a preview',
      () async {
        final saves = <PlannerState>[];
        final controller = PlannerApplicationController(
          catalog: _catalog(),
          initialState: _document().copyWith(plannerContentScale: 1.1),
          saveState: (state) async {
            saves.add(state);
            return state;
          },
          saveDebounce: Duration.zero,
        );
        controller.previewPlannerContentScale(1.24);
        controller.switchMode(CraftMode.cooking);
        controller.updateDocument(
          (state) => state.copyWith(showDeleteTools: true),
        );
        await controller.flush();
        expect(controller.plannerContentScale.value, 1.24);
        expect(saves, isNotEmpty);
        expect(
          saves.every((state) => state.plannerContentScale == 1.1),
          isTrue,
        );
        controller.cancelPlannerContentScalePreview();
        expect(controller.plannerContentScale.value, 1.1);
        controller.previewPlannerContentScale(1.2);
        final savedCount = saves.length;
        await controller.dispose();
        expect(saves, hasLength(savedCount));
      },
    );

    test(
      'committed size survives native reload and imported changes notify',
      () async {
        final controller = _controller();
        controller.commitPlannerContentScale(1.2);
        await controller.flush();
        const codec = PlannerStateJsonCodec();
        final saved = codec.decode(codec.encode(controller.documentSnapshot));
        await controller.dispose();
        final restored = PlannerApplicationController(
          catalog: _catalog(),
          initialState: saved,
          saveState: (state) async => state,
        );
        expect(restored.plannerContentScale.value, 1.2);
        restored.previewPlannerContentScale(1.25);
        restored.updateDocument(
          (state) => state.copyWith(plannerContentScale: 1.15),
        );
        expect(restored.plannerContentScale.value, 1.15);
        expect(restored.documentSnapshot.plannerContentScale, 1.15);
        await restored.dispose();
      },
    );

    test(
      'mode-change dismissal commits preview without reverting the mode',
      () async {
        final saves = <PlannerState>[];
        final controller = PlannerApplicationController(
          catalog: _catalog(),
          initialState: _document(),
          saveState: (state) async {
            saves.add(state);
            return state;
          },
          saveDebounce: Duration.zero,
        );
        final plans = {
          for (final entry in controller.modes.entries)
            entry.key: entry.value.plan.value,
        };
        var notifications = 0;
        controller.activeMode.addListener(() {
          notifications++;
          expect(
            controller.documentSnapshot.activeMode,
            controller.activeMode.value,
          );
          controller.commitPlannerContentScale();
        });
        controller.previewPlannerContentScale(1.2);
        controller.switchMode(CraftMode.cooking);
        await controller.flush();
        expect(notifications, 1);
        expect(controller.activeMode.value, CraftMode.cooking);
        expect(controller.documentSnapshot.activeMode, CraftMode.cooking);
        expect(controller.documentSnapshot.plannerContentScale, 1.2);
        expect(saves, isNotEmpty);
        expect(
          saves.every((state) => state.activeMode == CraftMode.cooking),
          isTrue,
        );
        expect(
          saves.every((state) => state.plannerContentScale == 1.2),
          isTrue,
        );
        for (final entry in controller.modes.entries) {
          expect(entry.value.plan.value, same(plans[entry.key]));
        }
        await controller.dispose();
      },
    );

    test(
      'values are bounded and frozen or disposed controllers reject edits',
      () async {
        final controller = _controller();
        controller.previewPlannerContentScale(8);
        expect(controller.plannerContentScale.value, 1.25);
        controller.previewPlannerContentScale(.4);
        expect(controller.plannerContentScale.value, 1);
        controller.previewPlannerContentScale(double.nan);
        expect(controller.plannerContentScale.value, 1);
        controller.commitPlannerContentScale(double.infinity);
        expect(controller.documentSnapshot.plannerContentScale, 1);
        controller.freezeMutationsForRestart();
        controller.previewPlannerContentScale(1.2);
        controller.commitPlannerContentScale(1.2);
        expect(controller.plannerContentScale.value, 1);
        expect(controller.documentSnapshot.plannerContentScale, 1);
        controller.resumeMutationsAfterRestartFailure();
        controller.commitPlannerContentScale(4);
        expect(controller.documentSnapshot.plannerContentScale, 1.25);
        await controller.dispose();
        controller.previewPlannerContentScale(1.1);
        controller.commitPlannerContentScale(1.1);
        controller.cancelPlannerContentScalePreview();
        expect(controller.documentSnapshot.plannerContentScale, 1.25);
      },
    );

    test('failed durable import restores the prior reading size', () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(plannerContentScale: 1.1),
        saveState: (_) async => throw const FileSystemException('disk full'),
        saveDebounce: Duration.zero,
      );
      await expectLater(
        controller.updateDocumentDurably(
          (state) => state.copyWith(plannerContentScale: 1.25),
        ),
        throwsStateError,
      );
      expect(controller.documentSnapshot.plannerContentScale, 1.1);
      expect(controller.plannerContentScale.value, 1.1);
      await controller.dispose();
    });
  });

  test(
    'Bonus batches keep their own credits without erasing the main queue',
    () async {
      final controller = _controller();
      final mode = controller.active;
      mode.updateState(
        (state) => state.copyWith(
          bonusTarget: 'Bonus Potion',
          bonusWant: 80,
          recipeEdits: {
            'Bonus Potion': RecipeState(
              type: 'simple_alchemy',
              baseOutput: 1,
              ingredients: [IngredientState(name: 'Base', quantity: 3)],
            ),
          },
        ),
      );
      expect(_completeBatch(mode, 20), isTrue);
      final bonusPlan = controller.assembly.build(
        catalog: controller.catalog,
        mode: mode.mode,
        state: mode.state.value,
        targetOverride: 'Bonus Potion',
        wantOverride: 80,
      );
      final step = bonusPlan.steps.single;
      final progress = mode.inventoryBatchProgress(
        step: step,
        target: 'Bonus Potion',
        want: 80,
        progressKey: AfkCraftProgress.sessionKeyFor(
          targetName: 'Bonus Potion',
          recipeName: 'Bonus Potion',
          bonus: true,
        ),
        attemptsPerRound: 30,
      );
      expect(
        mode.completeInventoryBatch(
          step: step,
          progress: progress,
          completedBefore: 0,
          completedAfter: 30,
          bonus: true,
        ),
        isTrue,
      );
      expect(mode.plan.value.steps.single.count, 80);
      expect(
        controller.assembly
            .build(
              catalog: controller.catalog,
              mode: mode.mode,
              state: mode.state.value,
              targetOverride: 'Bonus Potion',
              wantOverride: 80,
            )
            .steps
            .single
            .count,
        50,
      );
      expect(mode.undoCompletion(), isTrue);
      expect(mode.state.value.inventory['Potion'], 20);
      expect(mode.plan.value.steps.single.count, 80);
      expect(mode.undoCompletion(), isTrue);
      expect(mode.plan.value.steps.single.count, 100);
      await controller.dispose();
    },
  );

  test(
    'inventory corrections cannot resurrect already removed craft credit',
    () async {
      final controller = _controller();
      final mode = controller.active;
      _completeBatch(mode, 40);
      mode.commitInventory('Potion', '0');
      expect(mode.plan.value.steps.single.count, 100);
      mode.commitInventory('Potion', '500');
      expect(mode.plan.value.steps.single.count, 100);
      await controller.dispose();
    },
  );

  test(
    'batch credits expected output rather than the AFK safety maximum',
    () async {
      final controller = _controller();
      final mode = controller.active;
      mode.updateState(
        (state) => state.copyWith(
          recipeEdits: {
            'Potion': RecipeState(
              type: 'alchemy',
              baseOutput: 1,
              outputMinimum: 1,
              outputMaximum: 4,
              ingredients: [IngredientState(name: 'Base', quantity: 2)],
            ),
          },
        ),
      );
      final initial = mode.plan.value.steps.single;
      final expected = initial.produced / initial.count * 10;
      expect(_completeBatch(mode, 10), isTrue);
      expect(mode.state.value.inventory['Potion'], expected);
      expect(expected, lessThan(40));
      expect(mode.undoCompletion(), isTrue);
      expect(mode.plan.value.steps.single.count, initial.count);
      await controller.dispose();
    },
  );

  test(
    'intermediate batch reduces Need First and undo restores its ingredients',
    () async {
      final controller = PlannerApplicationController(
        catalog: _queueInventoryCatalog(),
        initialState: _document().copyWith(
          alchemy: _mode(CraftMode.alchemy, 'Final'),
        ),
        saveState: (state) async => state,
      );
      final mode = controller.active;
      double missing(String name) =>
          mode.plan.value.missing.firstWhere((item) => item.name == name).need;
      final dustBefore = missing('Ancient Spirit Dust');
      final stonesBefore = missing('Black Stone');
      final step = mode.plan.value.steps.first;
      expect(step.name, 'Caphras Stone');
      expect(_completeBatch(mode, 40), isTrue);
      expect(mode.state.value.inventory['Caphras Stone'], 40);
      expect(missing('Ancient Spirit Dust'), dustBefore - 200);
      expect(missing('Black Stone'), stonesBefore - 40);
      expect(mode.undoCompletion(), isTrue);
      expect(missing('Ancient Spirit Dust'), dustBefore);
      expect(missing('Black Stone'), stonesBefore);
      await controller.dispose();
    },
  );

  test(
    'legacy progress-only batches never award historical output on opening',
    () async {
      final controller = _controller();
      final mode = controller.active;
      final key = AfkCraftProgress.sessionKeyFor(
        targetName: 'Potion',
        recipeName: 'Potion',
      );
      mode.updateState(
        (state) => state.copyWith(
          afkCraftProgress: {
            key: AfkCraftProgress(
              stepKey: key,
              targetName: 'Potion',
              targetAmount: 100,
              recipeName: 'Potion',
              planSignature: mode.afkPlanSignature(
                mode.plan.value.steps.single,
              ),
              totalAttempts: 100,
              attemptsPerRound: 40,
              completedAttempts: 40,
            ),
          },
        ),
      );
      final before = controller.documentSnapshot;
      final progress = mode.inventoryBatchProgress(
        step: mode.plan.value.steps.single,
        target: 'Potion',
        want: 100,
        progressKey: key,
        attemptsPerRound: 40,
      );
      expect(progress.completedAttempts, 0);
      expect(controller.documentSnapshot, same(before));
      expect(_completeBatch(mode, 40), isTrue);
      expect(mode.state.value.inventory['Potion'], 40);
      expect(mode.undoCompletion(), isTrue);
      expect(mode.state.value.inventory['Potion'] ?? 0, 0);
      expect(mode.state.value.afkCraftProgress[key]!.completedAttempts, 40);
      await controller.dispose();
    },
  );

  for (final ignoreOwned in [true, false]) {
    test(
      'batch output reduces remaining crafts with ignore owned $ignoreOwned',
      () async {
        final controller = _controller();
        final mode = controller.active;
        mode.setFullTargetAmount(ignoreOwned);
        mode.setIgnoreOwnedIngredients(ignoreOwned);
        mode.commitInventory('Base', '250');
        expect(_completeBatch(mode, 40), isTrue);
        expect(mode.state.value.inventory['Potion'], 40);
        expect(mode.state.value.inventory['Base'], 170);
        expect(mode.plan.value.steps.single.count, 60);
        expect(mode.plan.value.steps.single.ingredients.single.need, 120);
        expect(mode.state.value.ignoreTargetInventory, ignoreOwned);
        expect(mode.state.value.ignoreIngredientInventory, ignoreOwned);
        final remaining = mode.plan.value.steps.single;
        expect(mode.completeStep(remaining), isTrue);
        expect(mode.state.value.inventory['Potion'], 100);
        expect(mode.state.value.inventory['Base'], 50);
        expect(mode.undoCompletion(), isTrue);
        expect(mode.state.value.inventory['Potion'], 40);
        expect(mode.plan.value.steps.single.count, 60);
        expect(mode.undoCompletion(), isTrue);
        expect(mode.state.value.inventory['Potion'] ?? 0, 0);
        expect(mode.state.value.inventory['Base'], 250);
        expect(mode.plan.value.steps.single.count, 100);
        expect(mode.canUndoCompletion(), isFalse);
        await controller.dispose();
      },
    );
  }

  test(
    'Undo never invents inputs when starting inventory was empty or partial',
    () async {
      final controller = _controller();
      final mode = controller.active;
      for (final quantity in [0, 3]) {
        mode.commitInventory('Base', '$quantity');
        expect(mode.completeStep(mode.plan.value.steps.single), isTrue);
        expect(mode.undoCompletion(), isTrue);
        expect(mode.state.value.inventory['Base'] ?? 0, quantity);
        expect(mode.state.value.inventory['Potion'] ?? 0, 0);
        expect(mode.state.value.completedSteps, isEmpty);
      }
      await controller.dispose();
    },
  );

  test(
    'batch undo restores the exact previous load after capacity changes',
    () async {
      final controller = _controller();
      final mode = controller.active;
      expect(_completeBatch(mode, 40), isTrue);
      expect(_completeBatch(mode, 30), isTrue);
      expect(mode.state.value.inventory['Potion'], 70);
      expect(mode.undoCompletion(), isTrue);
      expect(mode.state.value.inventory['Potion'], 40);
      expect(mode.plan.value.steps.single.count, 60);
      final progress = mode.state.value.afkCraftProgress.values.single;
      expect(progress.completedAttempts, 40);
      expect(progress.attemptsPerRound, 40);
      expect(_completeBatch(mode, 60), isTrue);
      expect(mode.state.value.inventory['Potion'], 100);
      expect(mode.plan.value.steps, isEmpty);
      expect(mode.undoAllInventoryBatches(progress.stepKey), isTrue);
      expect(mode.state.value.inventory['Potion'] ?? 0, 0);
      expect(mode.plan.value.steps.single.count, 100);
      await controller.dispose();
    },
  );

  test(
    'completion receipts survive save/reload and preserve unrelated edits',
    () async {
      final first = _controller();
      first.active.commitInventory('Base', '250');
      _completeBatch(first.active, 40);
      _completeBatch(first.active, 30);
      const codec = PlannerStateJsonCodec();
      final saved = codec.decode(codec.encode(first.documentSnapshot));
      await first.dispose();
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: saved,
        saveState: (state) async => state,
      );
      controller.active.commitInventory('Unrelated', '999');
      controller.active.toggleFavorite('Potion');
      expect(controller.active.undoCompletion(), isTrue);
      expect(controller.active.state.value.inventory['Potion'], 40);
      expect(controller.active.state.value.inventory['Unrelated'], 999);
      expect(controller.active.state.value.favoriteRecipes, contains('Potion'));
      expect(controller.active.undoCompletion(), isTrue);
      for (final mode in controller.modes.values) {
        expect(mode.state.value.inventory['Base'], 250);
        expect(mode.state.value.inventory['Potion'] ?? 0, 0);
      }
      await controller.dispose();
    },
  );

  test(
    'Undo refuses to overwrite a subsequent edit of the same item',
    () async {
      final controller = _controller();
      _completeBatch(controller.active, 40);
      controller.active.commitInventory('Potion', '75');
      final before = controller.documentSnapshot;
      expect(controller.active.undoCompletion(), isFalse);
      expect(controller.documentSnapshot, same(before));
      expect(controller.active.state.value.inventory['Potion'], 75);
      await controller.dispose();
    },
  );

  test(
    'stale repeated batch clicks and frozen completions cannot double credit',
    () async {
      final controller = _controller();
      final mode = controller.active;
      final step = mode.plan.value.steps.single;
      final progress = mode.inventoryBatchProgress(
        step: step,
        target: 'Potion',
        want: 100,
        progressKey: AfkCraftProgress.sessionKeyFor(
          targetName: 'Potion',
          recipeName: 'Potion',
        ),
        attemptsPerRound: 40,
      );
      bool click() => mode.completeInventoryBatch(
        step: step,
        progress: progress,
        completedBefore: 0,
        completedAfter: 40,
      );
      controller.freezeMutationsForRestart();
      expect(click(), isFalse);
      expect(mode.completeStep(step), isFalse);
      controller.resumeMutationsAfterRestartFailure();
      expect(click(), isTrue);
      expect(click(), isFalse);
      expect(mode.completeStep(step), isFalse);
      expect(mode.state.value.inventory['Potion'], 40);
      controller.freezeMutationsForRestart();
      expect(mode.undoCompletion(), isFalse);
      controller.resumeMutationsAfterRestartFailure();
      expect(mode.undoCompletion(), isTrue);
      await controller.dispose();
      expect(click(), isFalse);
    },
  );

  test(
    'full target counts only new crafts without spending pre-existing output',
    () async {
      final controller = _controller();
      final mode = controller.active;
      mode.commitInventory('Potion', '500');
      expect(_completeBatch(mode, 40), isTrue);
      expect(mode.state.value.inventory['Potion'], 540);
      expect(mode.plan.value.steps.single.count, 60);
      expect(mode.undoCompletion(), isTrue);
      expect(mode.state.value.inventory['Potion'], 500);
      expect(mode.plan.value.steps.single.count, 100);
      await controller.dispose();
    },
  );

  test(
    'shared inventory completion history undoes in order across modes',
    () async {
      final controller = _controller();
      controller.active.commitInventory('Base', '500');
      _completeBatch(controller.active, 40);
      final cooking = controller.modes[CraftMode.cooking]!;
      _completeBatch(cooking, 20);
      expect(controller.active.canUndoCompletion(), isFalse);
      expect(cooking.undoCompletion(), isTrue);
      expect(controller.active.undoCompletion(), isTrue);
      expect(controller.active.state.value.inventory['Base'], 500);
      await controller.dispose();
    },
  );

  test(
    'map favorites round-trip materials and typed locations without touching inventory',
    () async {
      final saved = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saved.add(state);
          return state;
        },
      );
      final inventoryBefore = Map<String, double>.of(
        controller.documentSnapshot.alchemy.inventory,
      );
      const keys = <String>{
        'ash',
        'map:fieldSource:field-source:dairy-cow',
        'map:workerNode:123',
      };
      controller.setResourceMapFavoriteIds(keys);
      await controller.flush();
      final reloaded = PlannerApplicationController(
        catalog: _catalog(),
        initialState: saved.last,
        saveState: (state) async => state,
      );
      expect(reloaded.resourceMapFavoriteIds.value, keys);
      expect(reloaded.documentSnapshot.alchemy.inventory, inventoryBefore);
      reloaded.setResourceMapFavoriteIds({'ash', 'map:workerNode:123'});
      expect(reloaded.resourceMapFavoriteIds.value, {
        'ash',
        'map:workerNode:123',
      });
      await reloaded.dispose();
      await controller.dispose();
    },
  );

  test(
    'planner actions keep planner state scoped and Inventory shared',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );
      final alchemy = controller.modes[CraftMode.alchemy]!;

      expect(alchemy.selectTarget('Potion'), isTrue);
      expect(alchemy.commitAmount('-3.8'), isTrue);
      expect(alchemy.state.value.want, 1);
      alchemy.setFullTargetAmount(false);
      alchemy.setIgnoreOwnedIngredients(false);
      alchemy.toggleCompleted('Potion');
      alchemy.toggleIngredients('Potion');
      expect(alchemy.addMissingAmount('Base', 4), isTrue);

      expect(alchemy.state.value.ignoreTargetInventory, isFalse);
      expect(alchemy.state.value.ignoreIngredientInventory, isFalse);
      expect(alchemy.state.value.completedSteps, contains('Potion'));
      expect(alchemy.expandedSteps.value, contains('Potion'));
      expect(alchemy.state.value.inventory['Base'], 4);
      for (final mode in CraftMode.values) {
        expect(controller.modes[mode]!.state.value.inventory['Base'], 4);
      }

      await controller.flush();
      expect(saves, isNotEmpty);
      expect(saves.last.alchemy.inventory['Base'], 4);
      await controller.dispose();
    },
  );

  test('invalid amount and inventory input leave state unchanged', () async {
    final controller = _controller();
    final mode = controller.active;

    expect(mode.commitAmount(''), isFalse);
    expect(mode.commitInventory('Base', '-1'), isFalse);
    expect(mode.state.value.want, 100);
    expect(mode.state.value.inventory, isEmpty);

    await controller.dispose();
  });

  test(
    'Need First Add updates shared inventory and owned-material planning atomically',
    () async {
      final controller = _controller();
      final mode = controller.active;
      const name = 'Imperfect Lightstone of Flora';
      var notifications = 0;
      mode.state.addListener(() => notifications += 1);

      expect(mode.state.value.ignoreIngredientInventory, isTrue);
      expect(mode.addMissingAmount(name, 12), isTrue);

      expect(notifications, 1);
      expect(mode.state.value.ignoreIngredientInventory, isFalse);
      for (final craftMode in CraftMode.values) {
        expect(controller.modes[craftMode]!.state.value.inventory[name], 12);
      }
      expect(
        controller
            .modes[CraftMode.cooking]!
            .state
            .value
            .ignoreIngredientInventory,
        isTrue,
      );

      final snapshot = controller.documentSnapshot;
      expect(mode.addMissingAmount(name, 0), isFalse);
      expect(mode.addMissingAmount(name, double.nan), isFalse);
      expect(identical(controller.documentSnapshot, snapshot), isTrue);
      expect(notifications, 1);

      controller.freezeMutationsForRestart();
      expect(mode.addMissingAmount(name, 4), isFalse);
      expect(mode.state.value.inventory[name], 12);
      expect(notifications, 1);

      await controller.dispose();
      expect(mode.addMissingAmount(name, 4), isFalse);
    },
  );

  test(
    'queue inventory sets a shared total and planning flags atomically',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );
      final mode = controller.active;
      mode.commitInventory('Base', '100');
      var notifications = 0;
      mode.state.addListener(() => notifications++);

      expect(mode.commitQueueInventory('Base', '25.430'), isTrue);
      expect(notifications, 1);
      expect(mode.state.value.ignoreIngredientInventory, isFalse);
      expect(mode.state.value.ignoreTargetInventory, isTrue);
      for (final craftMode in CraftMode.values) {
        expect(
          controller.modes[craftMode]!.state.value.inventory['Base'],
          25430,
        );
      }
      expect(
        controller
            .modes[CraftMode.cooking]!
            .state
            .value
            .ignoreIngredientInventory,
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        saves,
        isNotEmpty,
        reason: 'A queue edit saves immediately, not after the debounce.',
      );
      expect(saves.last.alchemy.inventory['Base'], 25430);

      expect(mode.commitQueueInventory('potion', '20'), isTrue);
      expect(mode.state.value.ignoreTargetInventory, isFalse);
      expect(mode.plan.value.steps.single.net, 80);
      expect(mode.commitQueueInventory('potion', '0'), isTrue);
      expect(mode.state.value.inventory.containsKey('potion'), isFalse);
      expect(mode.plan.value.steps.single.net, 100);
      await controller.dispose();
    },
  );

  test(
    'queue inventory removes covered intermediates but keeps shared needs',
    () async {
      final controller = PlannerApplicationController(
        catalog: _queueInventoryCatalog(),
        initialState: _document().copyWith(
          alchemy: _mode(CraftMode.alchemy, 'Final'),
        ),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      final mode = controller.active;
      double missing(String name) => mode.plan.value.missing
          .where((row) => row.name == name)
          .fold(0.0, (sum, row) => sum + row.missing);
      expect(missing('Ancient Spirit Dust'), 1500);
      expect(missing('Black Stone'), 500);

      expect(mode.commitQueueInventory('Caphras Stone', '150'), isTrue);
      expect(
        mode.plan.value.steps
            .firstWhere((step) => step.name == 'Caphras Stone')
            .count,
        150,
      );
      expect(missing('Ancient Spirit Dust'), 750);
      expect(missing('Black Stone'), 350);

      expect(mode.commitQueueInventory('Caphras Stone', '300'), isTrue);
      expect(
        mode.plan.value.steps.any((step) => step.name == 'Caphras Stone'),
        isFalse,
      );
      expect(missing('Ancient Spirit Dust'), 0);
      expect(
        missing('Black Stone'),
        200,
        reason: 'The final recipe still needs its own Black Stones.',
      );

      expect(mode.commitQueueInventory('Caphras Stone', '0'), isTrue);
      expect(missing('Ancient Spirit Dust'), 1500);
      expect(missing('Black Stone'), 500);
      await controller.dispose();
    },
  );

  test('queue inventory rejects invalid, frozen and disposed edits', () async {
    final controller = _controller();
    final mode = controller.active;
    final original = controller.documentSnapshot;
    for (final text in ['', '-1', 'not a number', 'NaN', 'Infinity']) {
      expect(mode.commitQueueInventory('Base', text), isFalse);
      expect(identical(controller.documentSnapshot, original), isTrue);
    }
    expect(mode.commitQueueInventory('   ', '10'), isFalse);
    controller.freezeMutationsForRestart();
    expect(mode.commitQueueInventory('Base', '10'), isFalse);
    expect(identical(controller.documentSnapshot, original), isTrue);
    controller.resumeMutationsAfterRestartFailure();
    expect(mode.commitQueueInventory('Base', '12,125'), isTrue);
    expect(mode.state.value.inventory['Base'], 12.125);
    await controller.dispose();
    expect(mode.commitQueueInventory('Base', '50'), isFalse);
  });

  test(
    'completing a queue step consumes inputs and adds output once',
    () async {
      final controller = _controller();
      final mode = controller.active;
      expect(mode.commitInventory('Base', '250'), isTrue);
      final step = mode.plan.value.steps.single;
      final consumedBase = step.ingredients
          .where((ingredient) => ingredient.name == 'Base')
          .fold<double>(0, (total, ingredient) => total + ingredient.need);

      expect(mode.completeStep(step), isTrue);
      final expectedBase = (250 - consumedBase).clamp(0, double.infinity);
      for (final craftMode in CraftMode.values) {
        final inventory = controller.modes[craftMode]!.state.value.inventory;
        expect(inventory['Base'] ?? 0, expectedBase);
        expect(inventory['Potion'], step.produced);
      }
      expect(mode.state.value.completedSteps, contains('Potion'));

      final afterFirst = Map<String, double>.of(mode.state.value.inventory);
      expect(mode.completeStep(step), isFalse);
      expect(mode.state.value.inventory, afterFirst);
      await controller.dispose();
    },
  );

  test(
    'Inventory stays available while Recipe Editor remains advanced',
    () async {
      final controller = _controller();
      final mode = controller.active;

      mode.navigate('inventory');
      expect(mode.state.value.view, 'inventory');
      mode.navigate('editor');
      expect(mode.state.value.view, 'plan');

      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
        immediate: true,
      );
      mode.navigate('inventory');
      expect(mode.state.value.view, 'inventory');
      mode.navigate('editor');
      expect(mode.state.value.view, 'editor');

      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: false),
        immediate: true,
      );
      mode.navigate('inventory');
      expect(mode.state.value.view, 'inventory');
      await controller.dispose();
    },
  );

  test(
    'owned amounts and completed steps survive save and Restart queue',
    () async {
      PlannerState? saved;
      final first = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saved = state;
          return state;
        },
        saveDebounce: Duration.zero,
      );
      final firstMode = first.active;
      firstMode.commitInventory('Base', '12.500');
      firstMode.toggleCompleted('Potion');
      await first.flush();
      expect(saved!.alchemy.inventory['Base'], 12500);
      expect(saved!.alchemy.completedSteps, contains('Potion'));
      await first.dispose();

      final restored = PlannerApplicationController(
        catalog: _catalog(),
        initialState: saved!,
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      expect(restored.active.state.value.inventory['Base'], 12500);
      expect(restored.active.state.value.completedSteps, contains('Potion'));

      restored.active.resetCompleted();
      expect(restored.active.state.value.completedSteps, isEmpty);
      expect(restored.active.state.value.inventory['Base'], 12500);
      expect(restored.active.state.value.target, 'Potion');
      expect(restored.active.state.value.want, 100);
      await restored.dispose();
    },
  );

  test(
    'document market tax notifier tracks edits without replacing mode state',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );
      final initialModeState = controller.active.state.value;
      final notifications = <MarketTax>[];
      controller.marketTax.addListener(
        () => notifications.add(controller.marketTax.value),
      );

      controller.updateDocument(
        (document) => document.copyWith(
          marketTax: document.marketTax.copyWith(
            valuePack: true,
            merchantRing: true,
            familyFameBonus: .015,
          ),
        ),
      );
      controller.updateDocument(
        (document) => document.copyWith(
          marketTax: document.marketTax.copyWith(enabled: false),
        ),
      );
      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
      );

      expect(
        identical(controller.active.state.value, initialModeState),
        isTrue,
      );
      expect(notifications, hasLength(2));
      expect(controller.marketTax.value.enabled, isFalse);
      expect(controller.marketTax.value.valuePack, isTrue);
      expect(controller.marketTax.value.merchantRing, isTrue);
      expect(controller.marketTax.value.familyFameBonus, .015);
      expect(
        identical(
          controller.marketTax.value,
          controller.documentSnapshot.marketTax,
        ),
        isTrue,
      );

      await controller.flush();
      expect(saves.last.marketTax.enabled, isFalse);
      expect(saves.last.marketTax.valuePack, isTrue);
      expect(saves.last.marketTax.merchantRing, isTrue);
      expect(saves.last.marketTax.familyFameBonus, .015);
      await controller.dispose();
    },
  );

  test(
    'AFK weight profile notifier tracks global settings and persisted state',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );
      final initialModeState = controller.active.state.value;
      final notifications = <AfkWeightProfile>[];
      controller.afkWeightProfile.addListener(
        () => notifications.add(controller.afkWeightProfile.value),
      );

      controller.updateDocument(
        (document) => document.copyWith(
          afkWeightProfile: document.afkWeightProfile.copyWith(
            maximumWeightLt: 1750,
            currentCarriedWeightLt: 120,
            safetyBufferLt: 25,
            featheryStepsLevel: 4,
          ),
        ),
      );

      expect(
        identical(controller.active.state.value, initialModeState),
        isTrue,
      );
      expect(notifications, hasLength(1));
      expect(controller.afkWeightProfile.value.maximumWeightLt, 1750);
      expect(controller.afkWeightProfile.value.safeLimitLt, 1955);
      expect(
        identical(
          controller.afkWeightProfile.value,
          controller.documentSnapshot.afkWeightProfile,
        ),
        isTrue,
      );

      await controller.flush();
      expect(saves.last.afkWeightProfile.maximumWeightLt, 1750);
      expect(saves.last.afkWeightProfile.featheryStepsLevel, 4);
      await controller.dispose();
    },
  );

  test(
    'resource map favorites load, persist deterministically, and preserve extensions',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'futureRoot': <String, Object?>{'revision': 7},
            'resourceMap': <String, Object?>{
              'futureMapPreference': 'compact',
              'favoriteResourceIds': <Object?>[
                ' snake-meat ',
                '',
                'worker-node:12',
                42,
                'snake-meat',
              ],
            },
          },
        ),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );

      expect(controller.resourceMapFavoriteIds.value, const <String>{
        'snake-meat',
        'worker-node:12',
      });

      controller.setResourceMapFavoriteIds(const <String>{
        'worker:lead',
        ' gathering:coral ',
        '',
      });

      expect(controller.resourceMapFavoriteIds.value, const <String>{
        'gathering:coral',
        'worker:lead',
      });
      expect(
        controller.documentSnapshot.extensions['futureRoot'],
        const <String, Object?>{'revision': 7},
      );
      final resourceMap =
          controller.documentSnapshot.extensions['resourceMap'] as Map;
      expect(resourceMap['futureMapPreference'], 'compact');
      expect(resourceMap['favoriteResourceIds'], const <String>[
        'gathering:coral',
        'worker:lead',
      ]);

      await controller.flush();
      expect(saves, hasLength(1));
      expect(
        (saves.single.extensions['resourceMap'] as Map)['favoriteResourceIds'],
        const <String>['gathering:coral', 'worker:lead'],
      );
      await controller.dispose();
    },
  );

  test(
    'resource map favorites notifier follows external document replacements',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async => state,
        saveDebounce: const Duration(days: 1),
      );
      final notifications = <Set<String>>[];
      controller.resourceMapFavoriteIds.addListener(
        () => notifications.add(controller.resourceMapFavoriteIds.value),
      );

      controller.updateDocument(
        (document) => document.copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['second', 'first'],
            },
          },
        ),
      );
      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
      );
      controller.updateDocument(
        (document) => document.copyWith(
          extensions: const <String, Object?>{'futureRoot': true},
        ),
      );

      expect(notifications, const <Set<String>>[
        <String>{'first', 'second'},
        <String>{},
      ]);
      await controller.dispose();
    },
  );

  test(
    'resource map interface style persists and rejects unknown values',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['ash'],
              'interfaceStyle': 'ghostLedger',
            },
          },
        ),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );

      expect(
        controller.resourceMapInterfaceStyle.value,
        ResourceMapInterfaceStyle.ghostLedger,
      );
      controller.setResourceMapInterfaceStyle(
        ResourceMapInterfaceStyle.glassDock,
      );
      expect(
        controller.resourceMapInterfaceStyle.value,
        ResourceMapInterfaceStyle.glassDock,
      );
      expect(
        (controller.documentSnapshot.extensions['resourceMap']
            as Map)['favoriteResourceIds'],
        const <String>['ash'],
      );
      expect(
        (controller.documentSnapshot.extensions['resourceMap'] as Map)
            .containsKey('interfaceStyle'),
        isFalse,
      );

      controller.updateDocument(
        (document) => document.copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{'interfaceStyle': 'future-style'},
          },
        ),
      );
      expect(
        controller.resourceMapInterfaceStyle.value,
        ResourceMapInterfaceStyle.glassDock,
      );

      controller.setResourceMapInterfaceStyle(
        ResourceMapInterfaceStyle.ghostLedger,
      );
      await controller.flush();
      expect(
        (saves.last.extensions['resourceMap'] as Map)['interfaceStyle'],
        'ghostLedger',
      );
      await controller.dispose();
    },
  );

  test(
    'resource map node network loads, persists, and preserves sibling settings',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['ash'],
              'nodeNetwork': <String, Object?>{
                'contributionPointBudget': 325,
                'desiredResourceNodeCounts': <String, int>{'ash': 2},
                'currentNodeIds': <String>['12', '8'],
                'currentOwnedHouseIds': <String>['2202', '2201'],
                'currentHouseUsageTypeIds': <String, int>{'2201': 2},
              },
            },
          },
        ),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );

      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .contributionPointBudget,
        325,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .desiredResourceNodeCounts,
        const <String, int>{'ash': 2},
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.onlineHoursPerDay,
        BdoNodeNetworkPreferences.defaultOnlineHoursPerDay,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .resourceAvailabilityPercent,
        BdoNodeNetworkPreferences.defaultResourceAvailabilityPercent,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .townWorkerCapacitiesByNodeId,
        isEmpty,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.mapVisualStyle,
        BdoMapVisualStyle.vivid,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.showCitiesAndTowns,
        isTrue,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.showGatewayHubs,
        isTrue,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.showAllMapNodes,
        isFalse,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .showAllNodeConnections,
        isFalse,
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .showWorkerOutputIcons,
        isFalse,
      );
      expect(
        controller.resourceMapNodeNetworkPreferences.value.currentOwnedHouseIds,
        const <String>{'2201', '2202'},
      );
      expect(
        controller
            .resourceMapNodeNetworkPreferences
            .value
            .currentHouseUsageTypeIds,
        const <String, int>{'2201': 2},
      );

      controller.setResourceMapNodeNetworkPreferences(
        BdoNodeNetworkPreferences(
          contributionPointBudget: 280,
          desiredResourceNodeCounts: const <String, int>{'fish': 3},
          currentNodeIds: const <String>{'24', '5'},
          currentOwnedHouseIds: const <String>{'2202', '2156'},
          currentHouseUsageTypeIds: const <String, int>{'2156': 1, '2202': 3},
          rootNodeIds: const <String>{'1'},
          onlineHoursPerDay: 10,
          resourceAvailabilityPercent: 65,
          useObservedTradeVolume: true,
          mapVisualStyle: BdoMapVisualStyle.vivid,
          showCitiesAndTowns: false,
          showGatewayHubs: false,
          showAllMapNodes: false,
          showAllNodeConnections: false,
          showWorkerOutputIcons: false,
          townWorkerCapacitiesByNodeId: const <String, BdoTownWorkerCapacity>{
            '100': BdoTownWorkerCapacity(
              availableWorkerCount: 4,
              freeLodgingSlotCount: 2,
              hiredWorkerCount: 4,
              bonusLodgingSlotCount: 8,
            ),
            '2': BdoTownWorkerCapacity(
              availableWorkerCount: 1,
              freeLodgingSlotCount: 0,
            ),
          },
        ),
      );

      expect(controller.resourceMapFavoriteIds.value, const <String>{'ash'});
      final resourceMap =
          controller.documentSnapshot.extensions['resourceMap'] as Map;
      final nodeNetwork = resourceMap['nodeNetwork'] as Map;
      expect(nodeNetwork['contributionPointBudget'], 280);
      expect(nodeNetwork['desiredResourceNodeCounts'], const <String, int>{
        'fish': 3,
      });
      expect(nodeNetwork['currentNodeIds'], const <String>['5', '24']);
      expect(nodeNetwork['currentOwnedHouseIds'], const <String>[
        '2156',
        '2202',
      ]);
      expect(nodeNetwork['currentHouseUsageTypeIds'], const <String, int>{
        '2156': 1,
        '2202': 3,
      });
      expect(nodeNetwork['rootNodeIds'], const <String>['1']);
      expect(
        nodeNetwork['schemaVersion'],
        BdoNodeNetworkPreferences.schemaVersion,
      );
      expect(nodeNetwork['onlineHoursPerDay'], 10);
      expect(nodeNetwork['resourceAvailabilityPercent'], 65);
      expect(nodeNetwork['useObservedTradeVolume'], isTrue);
      expect(nodeNetwork.containsKey('mapVisualStyle'), isFalse);
      expect(nodeNetwork['showCitiesAndTowns'], isFalse);
      expect(nodeNetwork['showGatewayHubs'], isFalse);
      expect(nodeNetwork['showAllMapNodes'], isFalse);
      expect(nodeNetwork['showAllNodeConnections'], isFalse);
      expect(nodeNetwork['showWorkerOutputIcons'], isFalse);
      expect(nodeNetwork['townWorkerCapacitiesByNodeId'], {
        '2': {'availableWorkerCount': 1, 'freeLodgingSlotCount': 0},
        '100': {
          'availableWorkerCount': 4,
          'freeLodgingSlotCount': 2,
          'hiredWorkerCount': 4,
          'bonusLodgingSlotCount': 8,
        },
      });

      await controller.flush();
      expect(saves, hasLength(1));
      const codec = PlannerStateJsonCodec();
      final restored = PlannerApplicationController(
        catalog: _catalog(),
        initialState: codec.decode(codec.encode(saves.single)),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      expect(
        restored.resourceMapNodeNetworkPreferences.value.sameValuesAs(
          controller.resourceMapNodeNetworkPreferences.value,
        ),
        isTrue,
      );
      expect(
        restored.resourceMapNodeNetworkPreferences.value.mapVisualStyle,
        BdoMapVisualStyle.vivid,
      );
      await restored.dispose();
      await controller.dispose();
    },
  );

  test(
    'gather checklist restores tolerant data, persists order, and preserves siblings',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'futureRoot': <String, Object?>{'revision': 9},
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['ash'],
              'futureMapPreference': 'compact',
              'gatherChecklist': <String, Object?>{
                'schemaVersion': 99,
                'entries': <Object?>[
                  <String, Object?>{
                    'resourceId': ' thuja ',
                    'displayName': ' Thuja Tree ',
                    'sourceKind': 'worker',
                  },
                  null,
                  <String, Object?>{
                    'resourceId': 'snake',
                    'displayName': 'Snake',
                    'completed': 'yes',
                  },
                  <String, Object?>{'resourceId': 'thuja', 'completed': true},
                  <String, Object?>{'resourceId': ' '},
                ],
                'selectedResourceId': 'snake',
              },
            },
          },
        ),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: const Duration(days: 1),
      );

      expect(
        controller.resourceMapGatherChecklist.value,
        BdoGatherChecklist(
          entries: <BdoGatherChecklistEntry>[
            BdoGatherChecklistEntry(
              resourceId: 'thuja',
              displayName: 'Thuja Tree',
              sourceKind: BdoGatherChecklistSourceKind.workerNode,
              isCompleted: true,
            ),
            BdoGatherChecklistEntry(
              resourceId: 'snake',
              displayName: 'Snake',
              isCompleted: true,
            ),
          ],
          selectedResourceId: 'snake',
        ),
      );

      final replacement = BdoGatherChecklist(
        entries: <BdoGatherChecklistEntry>[
          BdoGatherChecklistEntry(
            resourceId: 'rusalkas-coral',
            displayName: "Rusalka's Coral",
            sourceKind: BdoGatherChecklistSourceKind.manualGathering,
          ),
          BdoGatherChecklistEntry(
            resourceId: 'snake',
            displayName: 'Snake',
            sourceKind: BdoGatherChecklistSourceKind.manualGathering,
            isCompleted: true,
          ),
        ],
        selectedResourceId: 'rusalkas-coral',
      );
      controller.setResourceMapGatherChecklist(replacement);

      expect(controller.resourceMapGatherChecklist.value, replacement);
      expect(
        controller.documentSnapshot.extensions['futureRoot'],
        const <String, Object?>{'revision': 9},
      );
      final resourceMap =
          controller.documentSnapshot.extensions['resourceMap'] as Map;
      expect(resourceMap['favoriteResourceIds'], const <String>['ash']);
      expect(resourceMap['futureMapPreference'], 'compact');
      expect(resourceMap['gatherChecklist'], <String, Object?>{
        'schemaVersion': 2,
        'entries': <Object?>[
          <String, Object?>{
            'resourceId': 'rusalkas-coral',
            'displayName': "Rusalka's Coral",
            'sourceKind': 'manualGathering',
          },
          <String, Object?>{
            'resourceId': 'snake',
            'displayName': 'Snake',
            'sourceKind': 'manualGathering',
            'completed': true,
          },
        ],
        'selectedResourceId': 'rusalkas-coral',
      });

      await controller.flush();
      expect(saves, hasLength(1));
      expect(
        (saves.single.extensions['resourceMap'] as Map)['gatherChecklist'],
        replacement.toJson(),
      );
      await controller.dispose();
    },
  );

  test(
    'gather checklist follows document replacements and removes only its key when empty',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async => state,
        saveDebounce: const Duration(days: 1),
      );
      final notifications = <BdoGatherChecklist>[];
      controller.resourceMapGatherChecklist.addListener(
        () => notifications.add(controller.resourceMapGatherChecklist.value),
      );

      controller.updateDocument(
        (document) => document.copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['ash'],
              'gatherChecklist': <String, Object?>{
                'items': <Object?>[
                  <String, Object?>{
                    'materialId': 'snake',
                    'name': 'Snake',
                    'route': 'gather',
                  },
                  17,
                  false,
                ],
                'currentItemId': 'snake',
              },
            },
          },
        ),
      );
      controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
      );
      controller.setResourceMapGatherChecklist(BdoGatherChecklist());

      expect(notifications, hasLength(2));
      expect(
        notifications.first.entries.map((entry) => entry.resourceId),
        const <String>['snake', '17'],
      );
      expect(notifications.first.selectedResourceId, 'snake');
      expect(notifications.last, BdoGatherChecklist());
      final resourceMap =
          controller.documentSnapshot.extensions['resourceMap'] as Map;
      expect(resourceMap.containsKey('gatherChecklist'), isFalse);
      expect(resourceMap['favoriteResourceIds'], const <String>['ash']);
      await controller.dispose();
    },
  );

  test(
    'failed durable replacement restores gather checklist notifier',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'gatherChecklist': <String, Object?>{
                'entries': <Object?>[
                  <String, Object?>{'resourceId': 'original'},
                ],
              },
            },
          },
        ),
        saveState: (_) async {
          throw const FileSystemException('write failed');
        },
        saveDebounce: Duration.zero,
      );
      final notifications = <BdoGatherChecklist>[];
      controller.resourceMapGatherChecklist.addListener(
        () => notifications.add(controller.resourceMapGatherChecklist.value),
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            extensions: const <String, Object?>{
              'resourceMap': <String, Object?>{
                'gatherChecklist': <String, Object?>{
                  'entries': <Object?>[
                    <String, Object?>{'resourceId': 'replacement'},
                  ],
                },
              },
            },
          ),
        ),
        throwsStateError,
      );

      expect(
        notifications
            .map((checklist) => checklist.entries.single.resourceId)
            .toList(),
        const <String>['replacement', 'original'],
      );
      expect(
        controller.resourceMapGatherChecklist.value.entries.single.resourceId,
        'original',
      );
      await controller.dispose();
    },
  );

  test(
    'failed durable replacement restores resource map favorites notifier',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          extensions: const <String, Object?>{
            'resourceMap': <String, Object?>{
              'favoriteResourceIds': <String>['original'],
            },
          },
        ),
        saveState: (_) async {
          throw const FileSystemException('write failed');
        },
        saveDebounce: Duration.zero,
      );
      final notifications = <Set<String>>[];
      controller.resourceMapFavoriteIds.addListener(
        () => notifications.add(controller.resourceMapFavoriteIds.value),
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            extensions: const <String, Object?>{
              'resourceMap': <String, Object?>{
                'favoriteResourceIds': <String>['replacement'],
              },
            },
          ),
        ),
        throwsStateError,
      );

      expect(notifications, const <Set<String>>[
        <String>{'replacement'},
        <String>{'original'},
      ]);
      expect(controller.resourceMapFavoriteIds.value, const <String>{
        'original',
      });
      await controller.dispose();
    },
  );

  test('quantity commands accept de-DE decimal input', () async {
    final controller = _controller();
    final mode = controller.active;

    expect(mode.commitAmount('12,8'), isTrue);
    expect(mode.state.value.want, 12);
    expect(mode.commitInventory('Base', '1.234,5'), isTrue);
    expect(mode.state.value.inventory['Base'], 1234.5);

    await controller.dispose();
  });

  test(
    'market classification and trade evidence persist across mode switches',
    () async {
      final controller = _controller();
      final alchemy = controller.active;

      alchemy.replaceMarketValues(
        prices: const <String, double>{},
        stock: const <String, double>{},
        tradeMarketIds: const <String, String>{'Ore': '9'},
        totalTrades: const <String, int>{'Ore': 100},
        tradeObservedAt: const <String, int>{'Ore': 1000},
        observedDailyTrades: const <String, double>{'Ore': 24},
        tradeObservationHours: const <String, double>{'Ore': 6},
        lastSoldAtEpochSeconds: const <String, int>{'Ore': 900},
        unlistedItemNames: const <String>{'  BASE  '},
        fetchedAt: 42,
      );

      expect(alchemy.state.value.market.isItemUnlisted('Base'), isTrue);
      expect(
        controller.documentSnapshot.alchemy.market.unlistedItemNames,
        const <String>{'base'},
      );
      controller.switchMode(CraftMode.cooking);
      expect(controller.active.state.value.market.unlistedItemNames, isEmpty);
      controller.switchMode(CraftMode.alchemy);
      expect(
        controller.active.state.value.market.isItemUnlisted('BASE'),
        isTrue,
      );
      expect(
        controller.active.state.value.market.observedDailyTrades,
        const <String, double>{'Ore': 24},
      );
      expect(
        controller.active.state.value.market.tradeObservationHours,
        const <String, double>{'Ore': 6},
      );

      await controller.flush();
      await controller.dispose();
    },
  );

  test(
    'assembled recipes stay cached for unrelated state and invalidate safely',
    () async {
      final controller = _controller();
      final mode = controller.active;
      final initialRecipes = mode.recipes;

      mode.navigate('inventory');
      expect(identical(mode.recipes, initialRecipes), isTrue);
      mode.commitInventory('Base', '12');
      expect(identical(mode.recipes, initialRecipes), isTrue);

      mode.updateState(
        (state) => state.copyWith(hiddenItems: const <String>['Base']),
        immediate: true,
      );
      expect(identical(mode.recipes, initialRecipes), isFalse);
      expect(mode.recipes, isNot(contains('Base')));

      await controller.dispose();
    },
  );

  test(
    'legacy processing yield values persist without affecting plans',
    () async {
      final lowYield = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          activeMode: CraftMode.processing,
          processingYields: const <String, double>{
            'defaultYield': 1,
            'Grinding': .5,
          },
        ),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      final highYield = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document().copyWith(
          activeMode: CraftMode.processing,
          processingYields: const <String, double>{
            'defaultYield': 99,
            'Grinding': 77,
          },
        ),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );

      expect(
        lowYield.active.plan.value.toJson(),
        highYield.active.plan.value.toJson(),
      );
      expect(lowYield.documentSnapshot.processingYields['defaultYield'], 1);
      expect(highYield.documentSnapshot.processingYields['defaultYield'], 99);
      await lowYield.dispose();
      await highYield.dispose();
    },
  );

  test(
    'substitute, grade, reset, bonus target, and mode restore work',
    () async {
      final controller = _controller();
      final alchemy = controller.active;
      final ingredient = alchemy.recipes['Potion']!.ingredients.single;

      alchemy.selectSubstitute(
        parentName: 'Potion',
        ingredient: ingredient,
        selection: 'Other Base',
      );
      alchemy.selectIngredientGrade(
        parentName: 'Potion',
        ingredientName: 'Base',
        grade: 'high',
      );
      alchemy.toggleCompleted('Potion');
      alchemy.resetCompleted();
      alchemy.updateState(
        (state) =>
            state.copyWith(bonusTarget: 'Potion', bonusWant: 7, view: 'bonus'),
      );
      alchemy.useBonusAsTarget();

      expect(
        alchemy.state.value.substituteChoices.values,
        contains('Other Base'),
      );
      expect(alchemy.state.value.ingredientGrades.values, contains('high'));
      expect(alchemy.state.value.completedSteps, isEmpty);
      expect(alchemy.state.value.want, 7);
      expect(alchemy.state.value.view, 'plan');

      controller.switchMode(CraftMode.processing);
      controller.modes[CraftMode.processing]!.navigate('bonus');
      expect(controller.activeMode.value, CraftMode.processing);
      expect(controller.active.state.value.view, 'plan');
      await controller.dispose();
    },
  );

  test(
    'recipe variant choice is saved, recalculates, and survives market refresh',
    () async {
      final saves = <PlannerState>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          saves.add(state);
          return state;
        },
        saveDebounce: Duration.zero,
      );
      final mode = controller.active;
      mode.toggleCompleted('Potion');

      expect(mode.selectedRecipeVariantId('Potion'), 'base-route');
      expect(
        mode.selectRecipeVariant(
          recipeName: 'potion',
          variantId: 'ALTERNATE-ROUTE',
        ),
        isTrue,
      );
      expect(mode.state.value.recipeVariantChoices, {
        'Potion': 'alternate-route',
      });
      expect(mode.state.value.completedSteps, isNot(contains('Potion')));
      expect(
        mode.plan.value.steps.single.ingredients.single.name,
        'Variant Base',
      );
      expect(
        mode.availableIngredientGrades(
          parentName: 'Potion',
          selectedName: 'Variant Base',
        ),
        isEmpty,
        reason: 'the selected processing formula suppresses quality grades',
      );

      mode.replaceMarketValues(
        prices: const <String, double>{'Base': 1, 'Variant Base': 999},
        stock: const <String, double>{'Base': 999, 'Variant Base': 0},
        unlistedItemNames: const <String>{},
        fetchedAt: 12,
      );
      expect(mode.selectedRecipeVariantId('Potion'), 'alternate-route');
      expect(
        mode.plan.value.steps.single.ingredients.single.name,
        'Variant Base',
      );

      await controller.flush();
      expect(saves.last.alchemy.recipeVariantChoices, {
        'Potion': 'alternate-route',
      });
      await controller.dispose();
    },
  );

  test(
    'durable document update restores memory after a write failure',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (_) async => throw const FileSystemException('disk full'),
        saveDebounce: Duration.zero,
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            alchemy: document.alchemy.copyWith(target: 'Other Base'),
          ),
        ),
        throwsStateError,
      );

      expect(controller.documentSnapshot.alchemy.target, 'Potion');
      expect(controller.modes[CraftMode.alchemy]!.state.value.target, 'Potion');
      expect(controller.saveError.value, contains('disk full'));
      await controller.dispose();
    },
  );

  test(
    'failed durable update restores the document market tax notifier',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (_) async => throw const FileSystemException('disk full'),
        saveDebounce: Duration.zero,
      );
      final notifications = <MarketTax>[];
      controller.marketTax.addListener(
        () => notifications.add(controller.marketTax.value),
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            marketTax: document.marketTax.copyWith(
              enabled: false,
              valuePack: true,
              merchantRing: true,
              familyFameBonus: .015,
            ),
          ),
        ),
        throwsStateError,
      );

      expect(notifications.map((tax) => tax.enabled), const <bool>[
        false,
        true,
      ]);
      expect(controller.marketTax.value.enabled, isTrue);
      expect(controller.marketTax.value.valuePack, isFalse);
      expect(controller.marketTax.value.merchantRing, isFalse);
      expect(controller.marketTax.value.familyFameBonus, 0);
      expect(
        identical(
          controller.marketTax.value,
          controller.documentSnapshot.marketTax,
        ),
        isTrue,
      );
      await controller.dispose();
    },
  );

  test(
    'failed durable update restores the AFK weight profile notifier',
    () async {
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (_) async => throw const FileSystemException('disk full'),
        saveDebounce: Duration.zero,
      );
      final notifications = <double>[];
      controller.afkWeightProfile.addListener(
        () => notifications.add(
          controller.afkWeightProfile.value.maximumWeightLt,
        ),
      );

      await expectLater(
        controller.updateDocumentDurably(
          (document) => document.copyWith(
            afkWeightProfile: document.afkWeightProfile.copyWith(
              maximumWeightLt: 1900,
            ),
          ),
        ),
        throwsStateError,
      );

      expect(notifications, const <double>[1900, 0]);
      expect(controller.afkWeightProfile.value.maximumWeightLt, 0);
      expect(
        identical(
          controller.afkWeightProfile.value,
          controller.documentSnapshot.afkWeightProfile,
        ),
        isTrue,
      );
      await controller.dispose();
    },
  );

  test(
    'an older failed save cannot overwrite a newer durable update',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final savedTargets = <String>[];
      final controller = PlannerApplicationController(
        catalog: _catalog(),
        initialState: _document(),
        saveState: (state) async {
          savedTargets.add(state.alchemy.target);
          if (savedTargets.length == 1) {
            firstStarted.complete();
            await releaseFirst.future;
            throw const FileSystemException('first write failed');
          }
          return state;
        },
        saveDebounce: Duration.zero,
      );

      controller.updateDocument(
        (document) => document.copyWith(
          alchemy: document.alchemy.copyWith(target: 'Base'),
        ),
        immediate: true,
      );
      await firstStarted.future;
      final durable = controller.updateDocumentDurably(
        (document) => document.copyWith(
          alchemy: document.alchemy.copyWith(target: 'Other Base'),
        ),
      );
      releaseFirst.complete();
      await durable;
      await controller.flush();

      expect(savedTargets, const <String>['Base', 'Other Base']);
      expect(controller.documentSnapshot.alchemy.target, 'Other Base');
      expect(controller.saveError.value, isNull);
      await controller.dispose();
    },
  );

  test('first-run setup completes in one durable save', () async {
    final saves = <PlannerState>[];
    final controller = PlannerApplicationController(
      catalog: _catalog(),
      initialState: _document(),
      saveState: (state) async {
        saves.add(state);
        return state;
      },
      saveDebounce: Duration.zero,
    );

    await controller.finishFirstRunSetup(
      const FirstRunSetupAnswers(
        alchemyMastery: 1200,
        cookingMastery: 900,
        processingMastery: 1500,
        useMassProcessing: true,
        maximumWeightLt: 1900,
        currentCarriedWeightLt: 125,
        safetyBufferLt: 25,
        featheryStepsLevel: 3,
        valuePack: true,
        merchantRing: true,
        familyFameBonus: .015,
      ),
      groups: FirstRunSetupSchema.groups,
    );

    expect(saves, hasLength(1));
    expect(controller.documentSnapshot.alchemy.alchemyMastery, 1200);
    expect(controller.documentSnapshot.cooking.cookingMastery, 900);
    expect(controller.documentSnapshot.processing.processingMastery, 1500);
    expect(controller.documentSnapshot.processing.useMassProcessing, isTrue);
    expect(controller.documentSnapshot.afkWeightProfile.maximumWeightLt, 1900);
    expect(
      controller.documentSnapshot.afkWeightProfile.currentCarriedWeightLt,
      125,
    );
    expect(controller.documentSnapshot.afkWeightProfile.safetyBufferLt, 25);
    expect(controller.documentSnapshot.afkWeightProfile.featheryStepsLevel, 3);
    expect(controller.marketTax.value.valuePack, isTrue);
    expect(controller.marketTax.value.merchantRing, isTrue);
    expect(
      FirstRunSetupProgress.fromDocument(
        controller.documentSnapshot,
      ).shouldShow,
      isFalse,
    );
    await controller.dispose();
  });

  test('failed first-run setup save restores every prior value', () async {
    final initial = _document();
    final controller = PlannerApplicationController(
      catalog: _catalog(),
      initialState: initial,
      saveState: (_) async => throw const FileSystemException('disk full'),
      saveDebounce: Duration.zero,
    );

    await expectLater(
      controller.finishFirstRunSetup(
        const FirstRunSetupAnswers(
          alchemyMastery: 1200,
          cookingMastery: 900,
          processingMastery: 1500,
          useMassProcessing: true,
          maximumWeightLt: 1900,
          currentCarriedWeightLt: 125,
          safetyBufferLt: 25,
          featheryStepsLevel: 3,
          valuePack: true,
          merchantRing: true,
          familyFameBonus: .015,
        ),
        groups: FirstRunSetupSchema.groups,
      ),
      throwsStateError,
    );

    expect(identical(controller.documentSnapshot, initial), isTrue);
    expect(controller.active.state.value.alchemyMastery, 0);
    expect(controller.marketTax.value.valuePack, isFalse);
    expect(
      controller.documentSnapshot.extensions,
      isNot(contains(firstRunSetupExtensionKey)),
    );
    await controller.dispose();
  });
}

PlannerApplicationController _controller() => PlannerApplicationController(
  catalog: _catalog(),
  initialState: _document(),
  saveState: (state) async => state,
  saveDebounce: Duration.zero,
);

bool _completeBatch(ModeFeatureController mode, int attempts) {
  final step = mode.plan.value.steps.first;
  final progress = mode.inventoryBatchProgress(
    step: step,
    target: mode.state.value.target,
    want: mode.state.value.want,
    progressKey: AfkCraftProgress.sessionKeyFor(
      targetName: mode.state.value.target,
      recipeName: step.name,
    ),
    attemptsPerRound: attempts,
  );
  return mode.completeInventoryBatch(
    step: step,
    progress: progress,
    completedBefore: progress.completedAttempts,
    completedAfter: progress.completedAttempts + attempts,
  );
}

PlannerState _document() => PlannerState(
  applicationVersion: 'test',
  lastSuccessfulWriteUtc: DateTime.utc(2026),
  activeMode: CraftMode.alchemy,
  alchemy: _mode(CraftMode.alchemy, 'Potion'),
  cooking: _mode(CraftMode.cooking, 'Meal'),
  processing: _mode(CraftMode.processing, 'Flour'),
  processingYields: const {'defaultYield': 2.5},
  marketTax: MarketTax(),
);

ModeState _mode(CraftMode mode, String target) => ModeState(
  target: target,
  bonusTarget: target,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

CatalogSnapshot _queueInventoryCatalog() => CatalogSnapshot(
  sourceSha256: 'queue-inventory-fixture',
  sourceByteCount: 1,
  alchemy: ModeCatalog(
    mode: CraftMode.alchemy,
    items: {
      'Final': _recipe('Final', 'alchemy', [
        _queueIngredient('Caphras Stone', 3),
        _queueIngredient('Black Stone', 2),
      ]),
      'Caphras Stone': _recipe('Caphras Stone', 'processing', [
        _queueIngredient('Ancient Spirit Dust', 5),
        _queueIngredient('Black Stone', 1),
      ]),
      'Ancient Spirit Dust': _recipe('Ancient Spirit Dust', 'gathered', []),
      'Black Stone': _recipe('Black Stone', 'gathered', []),
    },
    iconDataUris: const {},
    defaults: const {},
    metadata: const {},
    searchAliases: const {},
  ),
  cooking: _modeCatalog(CraftMode.cooking, 'Meal'),
  processing: _modeCatalog(CraftMode.processing, 'Flour'),
  supportingData: const {},
  collisions: const [],
);

Ingredient _queueIngredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const [],
  substituteGroup: null,
  substituteRatios: const {},
);

CatalogSnapshot _catalog() => CatalogSnapshot(
  sourceSha256: 'fixture',
  sourceByteCount: 1,
  alchemy: _modeCatalog(CraftMode.alchemy, 'Potion'),
  cooking: _modeCatalog(CraftMode.cooking, 'Meal'),
  processing: _modeCatalog(CraftMode.processing, 'Flour'),
  supportingData: const {
    'qualityIngredients': <String>['Variant Base'],
  },
  collisions: const [],
);

ModeCatalog _modeCatalog(CraftMode mode, String target) => ModeCatalog(
  mode: mode,
  items: {
    target: _recipe(
      target,
      mode.key,
      [
        Ingredient(
          name: 'Base',
          quantity: 2,
          options: const ['Base', 'Other Base'],
          substituteGroup: 'bases',
          substituteRatios: const {'Other Base': 2},
        ),
      ],
      variants: <RecipeVariant>[
        RecipeVariant(
          id: 'base-route',
          label: 'Base Route',
          type: mode.key,
          baseOutput: 1,
          method: null,
          ingredients: <Ingredient>[
            Ingredient(
              name: 'Base',
              quantity: 2,
              options: const <String>['Base', 'Other Base'],
              substituteGroup: 'bases',
              substituteRatios: const <String, double>{'Other Base': 2},
            ),
          ],
          outputMinimum: 1,
          outputMaximum: 1,
        ),
        RecipeVariant(
          id: 'alternate-route',
          label: 'Alternate Route',
          type: 'processing',
          baseOutput: 1,
          method: null,
          ingredients: <Ingredient>[
            Ingredient(
              name: 'Variant Base',
              quantity: 3,
              options: const <String>[],
              substituteGroup: null,
              substituteRatios: const <String, double>{},
            ),
          ],
          outputMinimum: 1,
          outputMaximum: 1,
        ),
      ],
      defaultVariantId: 'base-route',
    ),
    'Base': _recipe('Base', 'gathered', const []),
    'Other Base': _recipe('Other Base', 'gathered', const []),
    'Variant Base': _recipe('Variant Base', 'gathered', const []),
  },
  iconDataUris: const {},
  defaults: const {},
  metadata: const {},
  searchAliases: const {},
);

Recipe _recipe(
  String name,
  String type,
  List<Ingredient> ingredients, {
  List<RecipeVariant> variants = const <RecipeVariant>[],
  String? defaultVariantId,
}) => Recipe(
  name: name,
  type: type,
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: ingredients,
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
  variants: variants,
  defaultVariantId: defaultVariantId,
);
