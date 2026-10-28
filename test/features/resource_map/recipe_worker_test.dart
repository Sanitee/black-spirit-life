import 'dart:convert';
import 'dart:io';
import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_catalog.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'recipe_worker_fixture.dart';

void main() {
  test('full chain sums repeated leaves rather than counting recipes', () {
    final leaves = workerCatalog().expand('Target');
    expect(
      {for (final l in leaves) l.name: l.quantity},
      {'A': 12, 'B': 2, 'Milk': 3},
    );
  });
  test('intermediate output is divided without per-step rounding', () {
    final catalog = RecipeWorkerCatalog({
      'Target': workerRecipe('Target', {'Part': 1}),
      'Part': workerRecipe('Part', {'A': 3}, output: 2),
    }, PlannerRules());
    expect(catalog.expand('Target').single.quantity, 1.5);
  });
  test('recipe cycles fail closed', () {
    final catalog = RecipeWorkerCatalog({
      'Target': workerRecipe('Target', {'Target': 1}),
    }, PlannerRules());
    expect(() => catalog.expand('Target'), throwsStateError);
  });
  test('demand 10:2 produces five A nodes for one B node', () {
    final allocator = BdoRecipeWorkerAllocator(
      data: workerMap(),
      economics: workerEconomics(),
      demands: workerDemands(),
    );
    final plan = allocator.allocate(8);
    expect(plan.nodesFor('A').length, 5);
    expect(plan.nodesFor('B').length, 1);
    expect(plan.spent, 8);
    expect(plan.remaining, 0);
    expect(allocator.add(plan), isNull);
  });
  test('slow B nodes receive more slots despite smaller recipe demand', () {
    final allocator = BdoRecipeWorkerAllocator(
      data: workerMap(),
      economics: workerEconomics(bWorkload: 5),
      demands: workerDemands(),
    );
    final plan = allocator.allocate(8);
    expect(plan.nodesFor('A').length, 3);
    expect(plan.nodesFor('B').length, 3);
  });
  test(
    'shared path charged once; removal keeps links used by another site',
    () {
      final allocator = BdoRecipeWorkerAllocator(
        data: workerMap(),
        economics: workerEconomics(),
        demands: workerDemands(),
      );
      var plan = allocator.allocate(4);
      expect(plan.paths.length, 2);
      expect(plan.spent, 4);
      plan = allocator.remove(plan, 'A')!;
      expect(plan.nodeIds, contains('bridge'));
      expect(plan.spent, 3);
      plan = allocator.remove(plan, 'B')!;
      expect(plan.spent, 0);
      expect(plan.nodeIds, isEmpty);
    },
  );
  test(
    'all eligible nodes selected with enough CP; budgets never exceeded',
    () {
      final allocator = BdoRecipeWorkerAllocator(
        data: workerMap(),
        economics: workerEconomics(),
        demands: workerDemands(),
      );
      for (var budget = 0; budget <= 20; budget++) {
        final plan = allocator.allocate(budget);
        expect(plan.spent, lessThanOrEqualTo(budget));
        expect(plan.paths.keys.toSet().length, plan.paths.length);
        if (budget < 3) expect(plan.paths, isEmpty);
        if (budget >= 14) expect(plan.paths.length, 12);
      }
    },
  );
  test('manual additions obey complete incremental route cost', () {
    final allocator = BdoRecipeWorkerAllocator(
      data: workerMap(),
      economics: workerEconomics(),
      demands: workerDemands(),
    );
    expect(allocator.add(allocator.restore(2, {}), demandId: 'A'), isNull);
    final plan = allocator.add(allocator.restore(3, {}), demandId: 'A')!;
    expect(plan.remaining, 0);
    expect(allocator.add(plan, demandId: 'B'), isNull);
  });
  test('restoring an intentionally empty selection does not repopulate it', () {
    final allocator = BdoRecipeWorkerAllocator(
      data: workerMap(),
      economics: workerEconomics(),
      demands: workerDemands(),
    );
    expect(allocator.restore(400, {}).paths, isEmpty);
    expect(allocator.restore(3, {'A0', 'B0'}).spent, lessThanOrEqualTo(3));
  });
  test('preferences round trip without overwriting legacy worker setup', () {
    final original = BdoNodeNetworkPreferences(
      currentNodeIds: {'old'},
      desiredResourceNodeCounts: {'A': 4},
      onlineHoursPerDay: 6,
    );
    final next = original.copyWith(
      recipeWorkers: BdoRecipeWorkerPreferences(
        target: 'Target',
        budget: 17,
        hasSelection: true,
        nodeIds: {'A0'},
        checkedItems: {'Milk'},
      ),
    );
    final restored = BdoNodeNetworkPreferences.fromJson(
      jsonDecode(jsonEncode(next.toJson())),
    );
    expect(restored.sameValuesAs(next), isTrue);
    expect(restored.currentNodeIds, {'old'});
    expect(restored.onlineHoursPerDay, 6);
    expect(restored.desiredResourceNodeCounts, {'A': 4});
    expect(
      restored.copyWith(showAllMapNodes: true).recipeWorkers.target,
      'Target',
    );
  });
  test(
    'restoring a saved budgeted plan retains its chosen sites and order',
    () {
      final allocator = BdoRecipeWorkerAllocator(
        data: workerMap(),
        economics: workerEconomics(),
        demands: workerDemands(),
      );
      final plan = allocator.allocate(8);
      final saved = BdoRecipeWorkerPreferences.fromJson(
        jsonDecode(
          jsonEncode(
            BdoRecipeWorkerPreferences(
              hasSelection: true,
              nodeIds: plan.paths.keys.toSet(),
              budget: 8,
            ).toJson(),
          ),
        ),
      );
      final restored = allocator.restore(saved.budget, saved.nodeIds);
      expect(restored.paths.keys.toList(), plan.paths.keys.toList());
      expect(restored.spent, plan.spent);
    },
  );
  test(
    'missing workload, yield or compatible town data is never fabricated',
    () {
      final base = workerEconomics();
      BdoWorkerProductionEconomics node({
        double workload = 1,
        Map<int, double> yields = const {1: 1},
        Map<String, double> distances = const {'root': 1},
        Iterable<int>? types,
      }) => BdoWorkerProductionEconomics(
        nodeId: 'A0',
        baseWorkload: workload,
        workerTypes: types ?? base.productionNodesById['A0']!.workerTypes,
        standardYields: yields,
        giantYields: {},
        luckyBonusYields: {},
        townDistances: distances,
      );
      for (final record in [
        null,
        node(workload: 0),
        node(yields: {}),
        node(distances: {}),
        node(types: []),
      ]) {
        final economy = BdoWorkerEconomicsDataset(
          schemaVersion: base.schemaVersion,
          manifest: base.manifest,
          townsByNodeId: base.townsByNodeId,
          productionNodesById: {'A0': ?record},
        );
        final allocator = BdoRecipeWorkerAllocator(
          data: workerMap(),
          economics: economy,
          demands: workerDemands(),
        );
        expect(allocator.available('A'), 0);
        expect(allocator.allocate(999).paths, isEmpty);
      }
    },
  );
  test(
    'bundled full recipes and real node data produce finite budgeted plans',
    () {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final recipes = <String, Recipe>{};
      for (final mode in [
        catalog.alchemy,
        catalog.cooking,
        catalog.processing,
      ]) {
        for (final r in mode.items.values) {
          if (r.isCraftable || recipes[r.name]?.isCraftable != true) {
            recipes[r.name] = r;
          }
        }
      }
      final source = RecipeWorkerCatalog(
        recipes,
        const PlannerAssembly().plannerRules(catalog.supportingData),
      );
      for (final name in source.targets) {
        final allLeaves = source.expand(name);
        expect(allLeaves, isNotEmpty, reason: name);
        expect(
          allLeaves.every(
            (leaf) => leaf.quantity.isFinite && leaf.quantity > 0,
          ),
          isTrue,
          reason: name,
        );
      }
      final data = BdoResourceMapDataset.fromJson(
        jsonDecode(
              File(
                'packages/bdo_map_core/assets/data/resource_map.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>,
      );
      final economics = BdoWorkerEconomicsDataset.fromJson(
        jsonDecode(
          File(
            'packages/bdo_map_core/assets/data/worker_economics.json',
          ).readAsStringSync(),
        ),
      );
      for (final name in ['Milk Tea', 'Harmony Draught - Edania', 'Beer']) {
        final leaves = source.expand(name);
        expect(leaves, isNotEmpty);
        expect(
          leaves.every((l) => l.quantity.isFinite && l.quantity > 0),
          isTrue,
        );
        final demands = RecipeWorkerCatalog.workerDemands(leaves, data);
        expect(demands, isNotEmpty, reason: name);
        final allocator = BdoRecipeWorkerAllocator(
          data: data,
          economics: economics,
          demands: demands,
        );
        final plan = allocator.allocate(78);
        expect(plan.spent, lessThanOrEqualTo(78));
        expect(plan.paths, isNotEmpty, reason: name);
        for (final node in plan.paths.keys) {
          expect(economics.productionNodesById, contains(node));
        }
      }
    },
  );
}
