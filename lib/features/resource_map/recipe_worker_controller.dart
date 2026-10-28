import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/foundation.dart';

import 'recipe_worker_catalog.dart';

enum RecipeWorkerPage { recipe, items, nodes }

class RecipeWorkerController extends ChangeNotifier {
  RecipeWorkerController({
    required this.catalogBuilder,
    required this.loadMap,
    required this.loadEconomics,
    required BdoRecipeWorkerPreferences initial,
    required this.onSave,
  }) : _targets = [...initial.targets],
       budget = initial.budget,
       checkedItems = {...initial.checkedItems},
       extraResourceIds = {...initial.extraResourceIds},
       manualNodeIds = {...initial.manualNodeIds},
       investedNodeIds = {...initial.investedNodeIds},
       _saved = initial;
  final RecipeWorkerCatalog Function() catalogBuilder;
  final Future<BdoResourceMapDataset> Function() loadMap;
  final Future<BdoWorkerEconomicsDataset> Function() loadEconomics;
  final ValueChanged<BdoRecipeWorkerPreferences> onSave;
  RecipeWorkerCatalog? catalog;
  BdoResourceMapDataset? data;
  BdoWorkerEconomicsDataset? economics;
  final List<String> _targets;
  List<String> get targets => List.unmodifiable(_targets);
  String get target => _targets.firstOrNull ?? '';
  int budget;
  Set<String> checkedItems;
  final Set<String> extraResourceIds, manualNodeIds, investedNodeIds;
  RecipeWorkerPage page = RecipeWorkerPage.recipe;
  String itemQuery = '';
  final scrollOffsets = <String, double>{};
  String get pageTitle => switch (page) {
    RecipeWorkerPage.recipe => 'Plan',
    RecipeWorkerPage.items => 'Add items',
    RecipeWorkerPage.nodes => 'Invest nodes',
  };
  void showPage(RecipeWorkerPage value) {
    page = value;
    notifyListeners();
  }

  bool back() {
    if (page == RecipeWorkerPage.recipe) return false;
    showPage(RecipeWorkerPage.recipe);
    return true;
  }

  final BdoRecipeWorkerPreferences _saved;
  List<RecipeWorkerLeaf> leaves = const [];
  Map<String, List<RecipeWorkerLeaf>> leavesByTarget = const {};
  Map<String, Set<String>> _ownersByResource = const {};
  List<RecipeWorkerGroup> get groups {
    final exclusive = {
      for (final name in targets) name: <BdoWorkerRecipeDemand>[],
    };
    final shared = <BdoWorkerRecipeDemand>[], added = <BdoWorkerRecipeDemand>[];
    final sharedOwners = <String>{};
    for (final demand in demands) {
      final owners = <String>{
        for (final resource in demand.resourceUnits.keys)
          ...?_ownersByResource[resource],
      };
      if (owners.length > 1) {
        shared.add(demand);
        sharedOwners.addAll(owners);
      } else if (owners.isNotEmpty) {
        exclusive[owners.single]!.add(demand);
      } else {
        added.add(demand);
      }
    }
    return [
      for (final entry in exclusive.entries)
        if (entry.value.isNotEmpty)
          RecipeWorkerGroup('recipe:${entry.key}', entry.key, [
            entry.key,
          ], entry.value),
      if (shared.isNotEmpty)
        RecipeWorkerGroup(
          'shared',
          'Shared',
          targets.where(sharedOwners.contains).toList(),
          shared,
        ),
      if (added.isNotEmpty)
        RecipeWorkerGroup('added', 'Added items', const [], added),
    ];
  }

  _WorkerView? _view;
  bool busy = false;
  String? error;
  int _revision = 0;
  bool _disposed = false;
  Future<void>? _loading;
  BdoRecipeWorkerPlan? get plan => _view?.plan;
  List<BdoWorkerRecipeDemand> get demands =>
      _view?.allocator.demands ?? const [];
  int available(String id) => _view?.allocator.available(id) ?? 0;
  bool canAdd(String id) => !busy && _view?.additions[id] != null;
  bool canRemove(String id) => !busy && _view?.removals[id] != null;
  List<BdoResourceDefinition> get addableItems =>
      (data?.resources
                .where((r) => data!.workerNodesForResource(r.id).isNotEmpty)
                .toList() ??
            [])
        ..sort((a, b) => a.name.compareTo(b.name));
  List<BdoWorkerNode> get investmentNodes {
    final paths = plan?.paths.values.toList() ?? <BdoProductionNodePath>[];
    paths.sort((a, b) {
      final root = (data?.workerNodesById[a.rootNodeId]?.name ?? a.rootNodeId)
          .compareTo(data?.workerNodesById[b.rootNodeId]?.name ?? b.rootNodeId);
      return root != 0 ? root : a.targetNodeId.compareTo(b.targetNodeId);
    });
    final roots = paths.map((p) => p.rootNodeId).toSet();
    // Follow each town's paths outward, keeping shared connections once.
    final ids = <String>{for (final path in paths) ...path.orderedNodeIds};
    return ids
        .where((id) => !roots.contains(id))
        .map((id) => data!.workerNodesById[id])
        .whereType<BdoWorkerNode>()
        .toList();
  }

  void toggleInvested(String id) {
    if (!investmentNodes.any((n) => n.id == id)) return;
    if (!investedNodeIds.remove(id)) investedNodeIds.add(id);
    _save();
    notifyListeners();
  }

  List<BdoGatheringPoint> pointsFor(String name) {
    final leaf = leaves.where((l) => l.name == name).firstOrNull;
    if (leaf == null || data == null) return const [];
    final resource = RecipeWorkerCatalog.resourceFor(leaf, data!);
    return resource == null
        ? const []
        : data!
              .gatheringPointsForResource(resource.id)
              .where((p) => p.location.x.isFinite && p.location.z.isFinite)
              .toList();
  }

  String pointSourceNote(String name) {
    final points = pointsFor(name);
    final ids = points.map((p) => p.provenanceId).toSet();
    final sources =
        data?.manifest.provenance
            .where((p) => ids.contains(p.id))
            .map((p) => '${p.title}\n${p.attribution}\n${p.url}')
            .join('\n\n') ??
        '';
    final historical = points.any(
      (p) => p.verification == BdoGatheringVerification.stale,
    );
    return '${historical ? 'Historical locations; not a current spawn guarantee.' : 'Recorded locations; not a rotation guide.'}\n\n$sources';
  }

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      catalog = catalogBuilder();
      final loaded = await Future.wait<Object>([loadMap(), loadEconomics()]);
      if (_disposed) return;
      data = loaded[0] as BdoResourceMapDataset;
      economics = loaded[1] as BdoWorkerEconomicsDataset;
      _targets.retainWhere(catalog!.targets.contains);
      if (target.isNotEmpty || extraResourceIds.isNotEmpty) {
        await _calculate(
          restore: _saved.hasSelection ? _saved.nodeIds : null,
          save: false,
        );
      }
    } catch (_) {
      error = 'Recipe data could not be loaded. Try again.';
      _loading = null;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> select(String name) async {
    // Single-target callers keep their existing replacement contract.
    if (_targets.length == 1 && name == target) return;
    if (name.isNotEmpty && !(catalog?.targets.contains(name) ?? false)) return;
    _targets
      ..clear()
      ..addAll([if (name.isNotEmpty) name]);
    _view = null;
    await _calculate();
  }

  Future<void> addRecipe(String name) async {
    if (busy ||
        _targets.contains(name) ||
        !(catalog?.targets.contains(name) ?? false)) {
      return;
    }
    _targets.add(name);
    await _calculate();
  }

  Future<void> replaceRecipe(String oldName, String name) async {
    final index = _targets.indexOf(oldName);
    if (busy ||
        index < 0 ||
        name == oldName ||
        _targets.contains(name) ||
        !(catalog?.targets.contains(name) ?? false)) {
      return;
    }
    _targets[index] = name;
    await _calculate();
  }

  Future<void> removeRecipe(String name) async {
    if (busy || !_targets.remove(name)) return;
    await _calculate();
  }

  Future<void> setBudget(int value) async {
    if (value < 0 || value == budget) return;
    budget = value;
    await _calculate();
  }

  Future<void> reset() => data == null ? load() : _calculate();
  Future<void> _calculate({Set<String>? restore, bool save = true}) async {
    final generation = ++_revision;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final source = catalog = catalogBuilder();
      if (data == null ||
          economics == null ||
          (target.isEmpty && extraResourceIds.isEmpty)) {
        _view = null;
        leaves = const [];
        leavesByTarget = const {};
        _ownersByResource = const {};
        checkedItems.clear();
        if (save && target.isEmpty) _save();
        return;
      }
      leavesByTarget = {for (final name in targets) name: source.expand(name)};
      leaves = RecipeWorkerCatalog.combine(leavesByTarget.values);
      checkedItems.retainAll(leaves.map((l) => l.name));
      final owners = <String, Set<String>>{};
      for (final entry in leavesByTarget.entries) {
        for (final demand in RecipeWorkerCatalog.workerDemands(
          entry.value,
          data!,
        )) {
          for (final resource in demand.resourceUnits.keys) {
            owners.putIfAbsent(resource, () => {}).add(entry.key);
          }
        }
      }
      _ownersByResource = owners;
      final job = _WorkerJob(
        data!,
        economics!,
        RecipeWorkerCatalog.workerDemands(leaves, data!),
        budget,
        restore,
        extraResourceIds,
        manualNodeIds,
      );
      final view = await compute(_allocate, job);
      if (_disposed || generation != _revision) return;
      _view = view;
      manualNodeIds.retainAll(view.plan.paths.keys);
      if (restore != null &&
          !view.plan.paths.keys.toSet().containsAll(restore)) {
        error =
            'Some saved nodes are unavailable or no longer fit. Review the selection.';
      }
      if (save) _save();
    } catch (_) {
      if (!_disposed && generation == _revision) {
        _view = null;
        error = 'This recipe could not be planned. Check its recipe data.';
      }
    } finally {
      if (!_disposed && generation == _revision) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> adjust(String id, {required bool add}) async {
    final view = _view;
    if (busy || view == null) return;
    final next = add ? view.additions[id] : view.removals[id];
    if (next == null) return;
    final revision = ++_revision;
    busy = true;
    notifyListeners();
    try {
      final updated = await compute(_prepareView, (view.allocator, next));
      if (_disposed || revision != _revision) return;
      _view = updated;
      manualNodeIds.retainAll(next.paths.keys);
      if (add && extraResourceIds.any((r) => 'extra:$r' == id)) {
        manualNodeIds.addAll(
          next.paths.keys.toSet().difference(view.plan.paths.keys.toSet()),
        );
      }
      _save();
    } catch (_) {
      if (!_disposed) {
        error = 'The node change could not be calculated. Try again.';
      }
    } finally {
      if (!_disposed && revision == _revision) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void toggle(String name) {
    if (!checkedItems.remove(name)) checkedItems.add(name);
    _save();
    notifyListeners();
  }

  /// Add one extra site's complete route without reallocating the current plan.
  /// Failure is non-mutating; it never silently frees CP or spends past budget.
  Future<bool> addItem(String resourceId) async {
    if (busy || _view == null || data == null || economics == null) {
      return false;
    }
    final resource = data!.resources
        .where((r) => r.id == resourceId)
        .firstOrNull;
    if (resource == null) return false;
    final existing = demands
        .where((d) => d.resourceUnits.containsKey(resourceId))
        .firstOrNull;
    if (existing != null) {
      if (!canAdd(existing.id)) return false;
      await adjust(existing.id, add: true);
      return true;
    }
    final revision = ++_revision;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final oldIds = plan!.paths.keys.toSet();
      final job = _WorkerJob(
        data!,
        economics!,
        RecipeWorkerCatalog.workerDemands(leaves, data!),
        budget,
        oldIds,
        {...extraResourceIds, resourceId},
        manualNodeIds,
      );
      final next = await compute(_addExtra, (job, 'extra:$resourceId'));
      if (_disposed || revision != _revision || next == null) return false;
      extraResourceIds.add(resourceId);
      manualNodeIds.addAll(next.plan.paths.keys.toSet().difference(oldIds));
      _view = next;
      _save();
      return true;
    } catch (_) {
      if (!_disposed) error = 'This item could not be added. Try again.';
      return false;
    } finally {
      if (!_disposed && revision == _revision) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void _save() => onSave(
    BdoRecipeWorkerPreferences(
      targets: targets,
      budget: budget,
      hasSelection: plan != null,
      nodeIds: plan?.paths.keys.toSet() ?? {},
      checkedItems: checkedItems,
      extraResourceIds: extraResourceIds,
      manualNodeIds: manualNodeIds,
      investedNodeIds: investedNodeIds,
    ),
  );
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}

class RecipeWorkerGroup {
  const RecipeWorkerGroup(this.id, this.title, this.recipes, this.demands);
  final String id, title;
  final List<String> recipes;
  final List<BdoWorkerRecipeDemand> demands;
}

class _WorkerJob {
  const _WorkerJob(
    this.data,
    this.economics,
    this.demands,
    this.budget,
    this.restore,
    this.extraResourceIds,
    this.manualNodeIds,
  );
  final BdoResourceMapDataset data;
  final BdoWorkerEconomicsDataset economics;
  final List<BdoWorkerRecipeDemand> demands;
  final int budget;
  final Set<String>? restore;
  final Set<String> extraResourceIds, manualNodeIds;
}

class _WorkerView {
  const _WorkerView(this.allocator, this.plan, this.additions, this.removals);
  final BdoRecipeWorkerAllocator allocator;
  final BdoRecipeWorkerPlan plan;
  final Map<String, BdoRecipeWorkerPlan?> additions, removals;
}

_WorkerView _allocate(_WorkerJob job) {
  final demands = [...job.demands];
  for (final r in job.data.resources.where(
    (r) => job.extraResourceIds.contains(r.id),
  )) {
    if (!demands.any((d) => d.resourceUnits.containsKey(r.id))) {
      demands.add(
        BdoWorkerRecipeDemand(
          id: 'extra:${r.id}',
          name: r.name,
          quantity: 1,
          resourceUnits: {r.id: 1},
        ),
      );
    }
  }
  final allocator = BdoRecipeWorkerAllocator(
    data: job.data,
    economics: job.economics,
    demands: demands,
  );
  final plan = job.restore == null
      ? allocator.allocate(
          job.budget,
          seedNodeIds: job.manualNodeIds,
          automaticDemandIds: job.demands.map((d) => d.id).toSet(),
        )
      : allocator.restore(job.budget, job.restore!);
  return _prepareView((allocator, plan));
}

_WorkerView? _addExtra((_WorkerJob, String) input) {
  final view = _allocate(input.$1);
  final next = view.allocator.add(view.plan, demandId: input.$2);
  return next == null ? null : _prepareView((view.allocator, next));
}

_WorkerView _prepareView(
  (BdoRecipeWorkerAllocator, BdoRecipeWorkerPlan) input,
) {
  final (allocator, plan) = input;
  return _WorkerView(
    allocator,
    plan,
    {
      for (final d in allocator.demands)
        d.id: allocator.add(plan, demandId: d.id),
    },
    {for (final d in allocator.demands) d.id: allocator.remove(plan, d.id)},
  );
}
