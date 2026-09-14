import 'dart:async';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/foundation.dart';

import '../../data/catalog/catalog_repository.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/planner/planner_models.dart' show PlanResult;
import '../../domain/state/inventory_storage.dart';
import '../../features/planner/planner_contracts.dart';
import '../state/planner_application_controller.dart';

/// Bridges the map's persisted requirements to the one shared inventory.
/// It never starts market requests or interprets a completion checkbox as stock.
class PlannerGatherChecklistBridge {
  PlannerGatherChecklistBridge({
    required this.controller,
    required this.catalog,
  }) {
    controller.resourceMapGatherChecklist.addListener(_queueSync);
    for (final mode in controller.modes.values) {
      mode.plan.addListener(_queueSync);
      mode.state.addListener(_queueSync);
    }
    _queueSync();
  }

  final PlannerApplicationController controller;
  final CatalogRepository catalog;
  bool _queued = false;
  bool _disposed = false;
  bool _writing = false;
  final Map<String, String> _keys = {};

  String materialKey(String name) =>
      _keys.putIfAbsent(name.trim().toLowerCase(), () {
        final ids = <String>{
          ?catalog.bundledMarketId(name),
          for (final mode in CraftMode.values)
            if (catalog.recipe(mode, name)?.marketId case final id?)
              if (id.trim().isNotEmpty) id,
        };
        return ids.length == 1
            ? 'item:${ids.single}'
            : 'name:${name.trim().toLowerCase()}';
      });

  BdoGatherChecklist add(PlannerGatherChecklistRequest request) {
    final source = request.availability;
    final differentRaw =
        source.manualMaterialName != null &&
        materialKey(source.manualMaterialName!) !=
            materialKey(source.materialName);
    final resourceId = differentRaw
        ? source.workerResourceId ?? source.manualResourceId
        : source.manualResourceId ?? source.workerResourceId;
    if (resourceId == null) {
      throw StateError('Choose an exact mapped material first.');
    }
    final isRawFallback = differentRaw && resourceId == source.manualResourceId;
    final name = isRawFallback
        ? source.manualMaterialName!
        : source.materialName;
    final key = materialKey(name);
    var current = controller.resourceMapGatherChecklist.value;
    // Preserve the user's first saved resource ID when another alias/source
    // resolves to the same actual inventory item.
    final existing = current.entries.where(
      (entry) =>
          entry.demands.any((demand) => demand.materialKey == key) ||
          (entry.displayName != null && materialKey(entry.displayName!) == key),
    );
    final entryId = existing.isEmpty ? resourceId : existing.first.resourceId;
    final demand = request.demand;
    BdoGatherChecklistDemand? contribution;
    if (!isRawFallback &&
        demand != null &&
        demand.neededQuantity.isFinite &&
        demand.neededQuantity >= 0 &&
        demand.sourceId.trim().isNotEmpty &&
        demand.sourceLabel.trim().isNotEmpty &&
        materialKey(demand.materialName) == key) {
      contribution = BdoGatherChecklistDemand(
        sourceId: demand.sourceId,
        sourceLabel: demand.sourceLabel,
        materialKey: key,
        materialName: demand.materialName,
        neededQuantity: demand.neededQuantity,
        plannerMode: demand.plannerMode?.key,
        plannerTarget: demand.plannerTarget,
        bonusPlan: demand.bonusPlan,
      );
      contribution = _refreshDemand(contribution, {});
    }
    current = current.addResource(
      resourceId: entryId,
      displayName: name,
      sourceKind: resourceId == source.manualResourceId
          ? BdoGatherChecklistSourceKind.manualGathering
          : BdoGatherChecklistSourceKind.workerNode,
      demands: [?contribution],
    );
    controller.setResourceMapGatherChecklist(current);
    return current;
  }

  void _queueSync() {
    if (_disposed || _queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (_disposed || _writing) return;
      synchronize();
    });
  }

  void synchronize() {
    final current = controller.resourceMapGatherChecklist.value;
    if (!current.entries.any(
      (e) => e.demands.any((d) => d.plannerMode != null),
    )) {
      return;
    }
    final bonusPlans = <String, PlanResult>{};
    final next = BdoGatherChecklist(
      selectedResourceId: current.selectedResourceId,
      entries: [
        for (final entry in current.entries)
          entry.copyWith(
            demands: [
              for (final demand in entry.demands)
                _refreshDemand(demand, bonusPlans),
            ],
          ),
      ],
    );
    if (next != current) controller.setResourceMapGatherChecklist(next);
  }

  BdoGatherChecklistDemand _refreshDemand(
    BdoGatherChecklistDemand demand,
    Map<String, PlanResult> bonusPlans,
  ) {
    final modes = CraftMode.values.where(
      (mode) => mode.key == demand.plannerMode,
    );
    if (modes.isEmpty || demand.plannerTarget == null) return demand;
    final mode = controller.modes[modes.single]!;
    final state = mode.state.value;
    final target = demand.bonusPlan ? state.bonusTarget : state.target;
    if (target.trim().toLowerCase() !=
        demand.plannerTarget!.trim().toLowerCase()) {
      return demand;
    }
    final plan = demand.bonusPlan
        ? bonusPlans.putIfAbsent(
            demand.plannerMode!,
            () => controller.assembly.build(
              catalog: controller.catalog,
              mode: mode.mode,
              state: state,
              targetOverride: target,
              wantOverride: state.bonusWant,
            ),
          )
        : mode.plan.value;
    // A deferred plan belonging to the previous target must not erase demand.
    if (plan.target.trim().toLowerCase() != target.trim().toLowerCase()) {
      return demand;
    }
    return demand.withQuantity(
      gatherNeededForPlan(plan, demand.materialKey, materialKey),
    );
  }

  Map<String, BdoGatherChecklistQuantity> quantities(
    BdoResourceMapDataset dataset,
  ) {
    final result = <String, BdoGatherChecklistQuantity>{};
    final seen = <String>{};
    for (final entry in controller.resourceMapGatherChecklist.value.entries) {
      final name = _recordName(entry, dataset);
      final key = name == null ? null : materialKey(name);
      final allDemands = key == null
          ? entry.demands
          : [
              for (final candidate
                  in controller.resourceMapGatherChecklist.value.entries)
                for (final demand in candidate.demands)
                  if (demand.materialKey == key) demand,
            ];
      final unique = {for (final demand in allDemands) demand.identity: demand};
      // Legacy aliases keep their IDs, but only one row allocates inventory.
      final first = key == null || seen.add(key);
      result[entry.resourceId] = BdoGatherChecklistQuantity(
        needed: first && unique.isNotEmpty
            ? unique.values.fold<double>(0, (sum, d) => sum + d.neededQuantity)
            : null,
        owned: name == null || !first ? null : _owned(key!),
        canRecord: name != null && first,
      );
    }
    return result;
  }

  String? _recordName(
    BdoGatherChecklistEntry entry,
    BdoResourceMapDataset dataset,
  ) {
    final resource = dataset.resourcesById[entry.resourceId];
    if (resource == null) return null;
    final name = resource.name;
    final key = materialKey(name);
    // Broad categories and processed-to-raw routes cannot identify a receipt.
    if (resource.gameItemId == null && !key.startsWith('item:')) return null;
    if (resource.gameItemId != null &&
        key.startsWith('item:') &&
        key != 'item:${resource.gameItemId}') {
      return null;
    }
    if (entry.demands.any((demand) => demand.materialKey != key)) return null;
    return name;
  }

  Map<String, double> _balances(String key) => {
    for (final entry in controller.documentSnapshot.alchemy.inventory.entries)
      if (materialKey(entry.key) == key) entry.key: entry.value,
  };

  double _owned(String key) => _balances(key).values.fold<double>(
    0,
    (amount, value) => value.isFinite && value > amount ? value : amount,
  );

  Future<BdoGatherChecklistReceipt> record(
    BdoResourceMapDataset dataset,
    String resourceId,
    double quantity,
  ) async {
    if (_writing || _disposed) {
      throw StateError('An inventory update is already in progress.');
    }
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError('Enter an amount above zero.');
    }
    final matches = controller.resourceMapGatherChecklist.value.entries.where(
      (e) => e.resourceId == resourceId,
    );
    if (matches.isEmpty) {
      throw StateError('This material is no longer in the to-do list.');
    }
    final name = _recordName(matches.single, dataset);
    if (name == null) {
      throw StateError('Choose an exact item before recording an amount.');
    }
    final key = materialKey(name);
    final previous = _balances(key);
    final owned = _owned(key);
    final balance = owned + quantity;
    if (!balance.isFinite) throw ArgumentError('The amount is too large.');
    final names = <String, String>{
      for (final alias in [
        name,
        ...previous.keys,
        for (final entry in controller.resourceMapGatherChecklist.value.entries)
          for (final demand in entry.demands)
            if (demand.materialKey == key) demand.materialName,
      ])
        alias.toLowerCase(): alias,
    };
    final deltas = {
      for (final alias in names.values)
        alias:
            balance -
            (previous.entries
                    .where((e) => e.key.toLowerCase() == alias.toLowerCase())
                    .firstOrNull
                    ?.value ??
                0),
    };
    late final Map<String, double> recorded;
    _writing = true;
    try {
      await controller.updateDocumentDurably((state) {
        final next = applySharedInventoryDeltas(state, deltas);
        recorded = {
          for (final entry in next.alchemy.inventory.entries)
            if (materialKey(entry.key) == key) entry.key: entry.value,
        };
        return next;
      });
    } finally {
      _writing = false;
      _queueSync();
    }
    var undone = false;
    return BdoGatherChecklistReceipt(
      undo: () async {
        if (_disposed || _writing || undone) {
          throw StateError('This gathered amount cannot be undone now.');
        }
        if (!mapEquals(recorded, _balances(key))) {
          throw StateError('Inventory changed since this amount was recorded.');
        }
        _writing = true;
        try {
          final undoDeltas = {
            for (final alias in recorded.keys)
              alias: (previous[alias] ?? 0) - recorded[alias]!,
          };
          await controller.updateDocumentDurably(
            (state) => applySharedInventoryDeltas(state, undoDeltas),
          );
          undone = true;
        } finally {
          _writing = false;
          _queueSync();
        }
      },
    );
  }

  void dispose() {
    _disposed = true;
    controller.resourceMapGatherChecklist.removeListener(_queueSync);
    for (final mode in controller.modes.values) {
      mode.plan.removeListener(_queueSync);
      mode.state.removeListener(_queueSync);
    }
  }
}

/// Includes fully owned ingredients, which PlanResult.missing intentionally
/// omits. A material used by several steps contributes its full combined need.
double gatherNeededForPlan(
  PlanResult plan,
  String key,
  String Function(String) keyFor,
) {
  final ingredients = [
    for (final step in plan.steps) ...step.ingredients,
  ].where((ingredient) => keyFor(ingredient.name) == key);
  if (ingredients.isNotEmpty) {
    return ingredients.fold<double>(0, (sum, item) => sum + item.need);
  }
  return plan.missing
      .where((item) => keyFor(item.name) == key)
      .fold<double>(0, (sum, item) => sum + item.need);
}
