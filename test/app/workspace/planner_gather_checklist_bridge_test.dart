import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/planner_gather_checklist_bridge.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/inventory_storage.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/planner/planner_test_fixture.dart';

void main() {
  late PlannerTestHarness fixture;
  late PlannerApplicationController controller;
  late PlannerGatherChecklistBridge bridge;
  var failSave = false;
  Completer<void>? blockedSave;

  setUp(() {
    failSave = false;
    blockedSave = null;
    fixture = PlannerTestHarness(
      supportingDataOverrides: {
        'marketIds': {
          'Sunrise Herb': '5400',
          'Sunrise alias': '5400',
          'Silver Azalea': '5402',
        },
      },
    );
    controller = PlannerApplicationController(
      catalog: fixture.controller.catalog,
      initialState: fixture.controller.documentSnapshot,
      saveDebounce: Duration.zero,
      saveState: (state) async {
        if (blockedSave != null) await blockedSave!.future;
        if (failSave) throw StateError('Disk unavailable');
        return state;
      },
    );
    bridge = PlannerGatherChecklistBridge(
      controller: controller,
      catalog: CatalogRepository(controller.catalog),
    );
  });
  tearDown(() async {
    bridge.dispose();
    failSave = false;
    if (blockedSave != null && !blockedSave!.isCompleted) {
      blockedSave!.complete();
    }
    await controller.dispose();
    await fixture.controller.dispose();
  });

  test(
    're-add replaces, plans sum, aliases and mirrored modes count Owned once',
    () async {
      controller.updateDocument(
        (state) => applySharedInventoryDeltas(state, {
          'Sunrise Herb': 7,
          'Sunrise alias': 7,
        }),
      );
      bridge.add(_request('a', 10));
      bridge.add(_request('a', 12));
      bridge.add(
        _request('b', 8, name: 'Sunrise alias', resourceId: 'alias-map-id'),
      );
      final list = controller.resourceMapGatherChecklist.value;
      expect(list.entries, hasLength(1));
      expect(list.entries.single.resourceId, 'herb');
      expect(list.entries.single.demands, hasLength(2));
      final quantity = bridge.quantities(_dataset())['herb']!;
      expect(quantity.needed, 20);
      expect(quantity.owned, 7);
      expect(quantity.remaining, 13);
      expect(controller.documentSnapshot.cooking.inventory['Sunrise Herb'], 7);
    },
  );

  test(
    'live amount and substitution update linked plan; inactive snapshot remains',
    () async {
      final mode = controller.active;
      final original = mode.plan.value;
      bridge.add(
        _request('live', 999, mode: mode.mode, target: original.target),
      );
      final before = controller
          .resourceMapGatherChecklist
          .value
          .entries
          .single
          .neededQuantity!;
      expect(before, lessThan(999));
      mode.commitAmount('${mode.state.value.want * 2}');
      await Future<void>.delayed(Duration.zero);
      final after = controller
          .resourceMapGatherChecklist
          .value
          .entries
          .single
          .neededQuantity!;
      expect(after, greaterThan(before));
      bridge.add(_request('snapshot', 3));
      controller.updateDocument(
        (state) => applySharedInventoryDeltas(state, {'Sunrise Herb': 100000}),
      );
      await Future<void>.delayed(Duration.zero);
      final quantity = bridge.quantities(_dataset())['herb']!;
      expect(quantity.needed, greaterThan(0));
      expect(quantity.remaining, 0);
      expect(
        controller
            .resourceMapGatherChecklist
            .value
            .entries
            .single
            .demands
            .last
            .neededQuantity,
        3,
      );
    },
  );

  test(
    'checkbox never acquires stock; explicit durable record + one undo does',
    () async {
      bridge.add(_request('a', 10));
      expect(controller.active.state.value.ignoreIngredientInventory, isTrue);
      controller.setResourceMapGatherChecklist(
        controller.resourceMapGatherChecklist.value.toggleCompletion('herb'),
      );
      expect(bridge.quantities(_dataset())['herb']!.owned, 0);
      final receipt = await bridge.record(_dataset(), 'herb', 4);
      for (final mode in controller.modes.values) {
        expect(mode.state.value.inventory['Sunrise Herb'], 4);
      }
      expect(bridge.quantities(_dataset())['herb']!.remaining, 6);
      expect(controller.active.state.value.ignoreIngredientInventory, isTrue);
      expect(
        controller.resourceMapGatherChecklist.value.entries.single.isCompleted,
        isTrue,
      );
      await receipt.undo();
      expect(bridge.quantities(_dataset())['herb']!.owned, 0);
      await expectLater(receipt.undo(), throwsStateError);
    },
  );

  test(
    'failed save rolls inventory back and retry records only once',
    () async {
      bridge.add(_request('a', 10));
      await controller.flush();
      failSave = true;
      await expectLater(bridge.record(_dataset(), 'herb', 4), throwsStateError);
      expect(bridge.quantities(_dataset())['herb']!.owned, 0);
      failSave = false;
      await bridge.record(_dataset(), 'herb', 4);
      expect(bridge.quantities(_dataset())['herb']!.owned, 4);
    },
  );

  test(
    'pending record prevents duplicate submission and later inventory blocks undo',
    () async {
      bridge.add(_request('a', 10));
      await controller.flush();
      blockedSave = Completer<void>();
      final first = bridge.record(_dataset(), 'herb', 4);
      await expectLater(bridge.record(_dataset(), 'herb', 4), throwsStateError);
      blockedSave!.complete();
      final receipt = await first;
      controller.updateDocument(
        (state) => applySharedInventoryDeltas(state, {'Sunrise Herb': -1}),
      );
      await expectLater(receipt.undo(), throwsStateError);
      expect(bridge.quantities(_dataset())['herb']!.owned, 3);
    },
  );

  test(
    'processed raw fallback carries no 1:1 demand and records only real raw item',
    () async {
      bridge.add(
        PlannerGatherChecklistRequest(
          availability: const PlannerMapLookupAvailability(
            materialName: 'Herb Powder',
            manualMaterialName: 'Sunrise Herb',
            manualResourceId: 'herb',
            hasManualGathering: true,
          ),
          demand: const PlannerGatherDemand(
            sourceId: 'powder',
            sourceLabel: 'Powder',
            materialName: 'Herb Powder',
            neededQuantity: 9,
          ),
        ),
      );
      final entry = controller.resourceMapGatherChecklist.value.entries.single;
      expect(entry.displayName, 'Sunrise Herb');
      expect(entry.demands, isEmpty);
      expect(bridge.quantities(_dataset())['herb']!.needed, isNull);
      await bridge.record(_dataset(), 'herb', 2);
      expect(controller.active.state.value.inventory['Sunrise Herb'], 2);
      expect(
        controller.active.state.value.inventory.containsKey('Herb Powder'),
        isFalse,
      );
      await expectLater(
        bridge.record(_dataset(), 'herb', double.nan),
        throwsArgumentError,
      );
    },
  );

  test(
    'record synchronizes actual aliases without multiplying gathered quantity',
    () async {
      controller.updateDocument(
        (state) => applySharedInventoryDeltas(state, {
          'Sunrise Herb': 7,
          'Sunrise alias': 7,
        }),
      );
      bridge.add(_request('a', 20));
      bridge.add(_request('b', 8, name: 'Sunrise alias'));
      final receipt = await bridge.record(_dataset(), 'herb', 3);
      expect(bridge.quantities(_dataset())['herb']!.owned, 10);
      expect(controller.active.state.value.inventory['Sunrise Herb'], 10);
      expect(controller.active.state.value.inventory['Sunrise alias'], 10);
      await receipt.undo();
      expect(bridge.quantities(_dataset())['herb']!.owned, 7);
    },
  );

  test(
    'inventory change while save awaits must not be adopted by the undo receipt',
    () async {
      bridge.add(_request('a', 10));
      await controller.flush();
      blockedSave = Completer<void>();
      final future = bridge.record(_dataset(), 'herb', 4);
      controller.updateDocument(
        (state) => applySharedInventoryDeltas(state, {'Sunrise Herb': 2}),
      );
      blockedSave!.complete();
      final receipt = await future;
      await expectLater(receipt.undo(), throwsStateError);
      expect(bridge.quantities(_dataset())['herb']!.owned, 6);
    },
  );

  test(
    'restoration retains demands and explicit zero; missing map identity cannot record',
    () async {
      bridge.add(_request('a', 0));
      final saved = controller.documentSnapshot;
      final reloaded = PlannerApplicationController(
        catalog: controller.catalog,
        initialState: saved,
        saveState: (state) async => state,
      );
      expect(
        reloaded.resourceMapGatherChecklist.value.entries.single.neededQuantity,
        0,
      );
      await reloaded.dispose();
      controller.setResourceMapGatherChecklist(
        controller.resourceMapGatherChecklist.value.addResource(
          resourceId: 'unknown',
          displayName: 'Unmapped item',
        ),
      );
      expect(bridge.quantities(_dataset())['unknown']!.canRecord, isFalse);
      await expectLater(
        bridge.record(_dataset(), 'unknown', 3),
        throwsStateError,
      );
    },
  );

  test(
    'recorded inventory reduces Planner missing when inventory is enabled',
    () async {
      final mode = controller.active;
      mode.updateState(
        (state) => state.copyWith(ignoreIngredientInventory: false),
      );
      final before = mode.plan.value.missing
          .where((item) => item.name == 'Sunrise Herb')
          .fold<double>(0, (sum, item) => sum + item.missing);
      expect(before, greaterThan(0));
      bridge.add(
        _request(
          'active',
          999,
          mode: mode.mode,
          target: mode.plan.value.target,
        ),
      );
      final receipt = await bridge.record(_dataset(), 'herb', 1);
      final after = mode.plan.value.missing
          .where((item) => item.name == 'Sunrise Herb')
          .fold<double>(0, (sum, item) => sum + item.missing);
      expect(after, closeTo((before - 1).clamp(0, double.infinity), .00001));
      expect(mode.state.value.ignoreIngredientInventory, isFalse);
      await receipt.undo();
      final restored = mode.plan.value.missing
          .where((item) => item.name == 'Sunrise Herb')
          .fold<double>(0, (sum, item) => sum + item.missing);
      expect(restored, before);
    },
  );

  test(
    'bonus is independent and inactive target keeps its saved requirement',
    () async {
      final mode = controller.active;
      final target = mode.state.value.target;
      bridge.add(_request('normal', 999, mode: mode.mode, target: target));
      bridge.add(
        _request('bonus', 999, mode: mode.mode, target: target, bonus: true),
      );
      Map<String, double> requirements() => {
        for (final demand
            in controller
                .resourceMapGatherChecklist
                .value
                .entries
                .single
                .demands)
          demand.sourceId: demand.neededQuantity,
      };
      final before = requirements();
      mode.updateState(
        (state) => state.copyWith(bonusWant: state.bonusWant * 3),
      );
      await Future<void>.delayed(Duration.zero);
      expect(requirements()['normal'], before['normal']);
      expect(requirements()['bonus'], greaterThan(before['bonus']!));
      final normalSnapshot = requirements()['normal'];
      expect(mode.selectTarget('Pure Powder Reagent'), isTrue);
      mode.commitAmount('200');
      await Future<void>.delayed(Duration.zero);
      expect(requirements()['normal'], normalSnapshot);
    },
  );
}

PlannerGatherChecklistRequest _request(
  String source,
  double amount, {
  String name = 'Sunrise Herb',
  String resourceId = 'herb',
  CraftMode? mode,
  String? target,
  bool bonus = false,
}) => PlannerGatherChecklistRequest(
  availability: PlannerMapLookupAvailability(
    materialName: name,
    manualResourceId: resourceId,
    hasManualGathering: true,
  ),
  demand: PlannerGatherDemand(
    sourceId: source,
    sourceLabel: source,
    materialName: name,
    neededQuantity: amount,
    plannerMode: mode,
    plannerTarget: target,
    bonusPlan: bonus,
  ),
);

BdoResourceMapDataset _dataset() => BdoResourceMapDataset(
  manifest: BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'test',
    provenance: const [],
  ),
  resources: const [
    BdoResourceDefinition(
      id: 'herb',
      name: 'Sunrise Herb',
      gameItemId: 5400,
      category: 'Herb',
      section: BdoResourceSection.plantsWood,
      aliases: [],
      acquisitionModes: {BdoAcquisitionMode.fieldGathering},
    ),
  ],
  workerNodes: const [],
  gatheringSpots: const [],
  gatheringRoutes: const [],
);
