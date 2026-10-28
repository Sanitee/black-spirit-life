import 'dart:convert';
import 'dart:io';
import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_catalog.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_controller.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'recipe_worker_fixture.dart';

RecipeWorkerCatalog groupedCatalog() => RecipeWorkerCatalog({
  'First': workerRecipe('First', {'Part': 2, 'Milk': 1}),
  'Part': workerRecipe('Part', {'A': 5}, output: 2),
  'Second': workerRecipe('Second', {'B': 2}),
  'Third': workerRecipe('Third', {'A': 3, 'B': 1, 'Milk': 2}),
}, PlannerRules());

void main() {
  test(
    'single-target migration, ordered targets, explicit empty, no duplicates',
    () {
      final old = BdoRecipeWorkerPreferences.fromJson({
        'target': 'First',
        'budget': 17,
        'nodeIds': ['A0'],
        'hasSelection': true,
      });
      expect(old.targets, ['First']);
      expect(old.budget, 17);
      expect(old.nodeIds, {'A0'});
      final next = BdoRecipeWorkerPreferences(
        targets: ['First', 'Second', 'First', ''],
        budget: 17,
      );
      final restored = BdoRecipeWorkerPreferences.fromJson(
        jsonDecode(jsonEncode(next.toJson())),
      );
      expect(restored.targets, ['First', 'Second']);
      expect(restored.target, 'First');
      expect(restored.sameValuesAs(next), isTrue);
      expect(
        restored.sameValuesAs(
          BdoRecipeWorkerPreferences(targets: ['Second', 'First'], budget: 17),
        ),
        isFalse,
      );
      expect(
        BdoRecipeWorkerPreferences.fromJson({
          'target': 'First',
          'targets': [],
        }).targets,
        isEmpty,
      );
    },
  );

  test(
    'combined demand sums fractional full chains and canonical item identities',
    () {
      final c = groupedCatalog();
      final combined = RecipeWorkerCatalog.combine([
        c.expand('First'),
        c.expand('Third'),
      ]);
      expect(
        {for (final l in combined) l.name: l.quantity},
        {'A': 8, 'B': 1, 'Milk': 3},
      );
      final aliases = RecipeWorkerCatalog.combine([
        [const RecipeWorkerLeaf('Same', 1.5, 1, false, true)],
        [const RecipeWorkerLeaf('Alias', 2.5, 1, false, true)],
      ]);
      expect(aliases.length, 1);
      expect(aliases.single.quantity, 4);
    },
  );

  test(
    'ownership regrouping, one shared demand, affordable selection, restore',
    () async {
      BdoRecipeWorkerPreferences? saved;
      RecipeWorkerController create(BdoRecipeWorkerPreferences initial) =>
          RecipeWorkerController(
            catalogBuilder: groupedCatalog,
            loadMap: () async => workerMap(),
            loadEconomics: () async => workerEconomics(),
            initial: initial,
            onSave: (v) => saved = v,
          );
      final c = create(
        BdoRecipeWorkerPreferences(targets: ['First', 'Second'], budget: 8),
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.error, isNull);
      expect(c.groups.map((g) => g.id), ['recipe:First', 'recipe:Second']);
      c.toggle('Milk');
      await c.addRecipe('Third');
      expect(c.targets, ['First', 'Second', 'Third']);
      expect(c.demands.map((d) => d.id), ['A', 'B']);
      expect(c.demands.first.quantity, 8);
      expect(c.groups.map((g) => g.id), ['shared']);
      expect(c.groups.single.recipes, ['First', 'Second', 'Third']);
      expect(c.checkedItems, {'Milk'});
      expect(c.plan!.spent, lessThanOrEqualTo(8));
      expect(c.plan!.nodeIds.where((n) => n == 'bridge').length, 1);
      final restored = create(
        BdoRecipeWorkerPreferences.fromJson(saved!.toJson()),
      );
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.targets, c.targets);
      expect(restored.plan!.paths.keys.toList(), c.plan!.paths.keys.toList());
      await c.removeRecipe('Third');
      expect(c.groups.map((g) => g.id), ['recipe:First', 'recipe:Second']);
      await c.replaceRecipe('Second', 'First');
      expect(c.targets, ['First', 'Second']);
      await c.addRecipe('First');
      expect(c.targets.length, 2);
      await c.removeRecipe('First');
      expect(c.checkedItems, isEmpty);
      for (final budget in [0, 2, 5, 12]) {
        await c.setBudget(budget);
        expect(c.plan!.spent, lessThanOrEqualTo(budget));
      }
      await c.removeRecipe('Second');
      expect(c.plan, isNull);
      expect(c.groups, isEmpty);
      expect(saved!.targets, isEmpty);
    },
  );

  test(
    'manual additions remain separate and funded after recipe removal',
    () async {
      final c = RecipeWorkerController(
        catalogBuilder: groupedCatalog,
        loadMap: () async => workerMap(),
        loadEconomics: () async => workerEconomics(),
        initial: BdoRecipeWorkerPreferences(target: 'First', budget: 10),
        onSave: (_) {},
      );
      addTearDown(c.dispose);
      await c.load();
      expect(await c.addItem('B'), isTrue);
      expect(c.groups.last.id, 'added');
      final ids = {...c.manualNodeIds};
      await c.addRecipe('Second');
      expect(c.groups.any((g) => g.id == 'added'), isFalse);
      await c.removeRecipe('First');
      await c.removeRecipe('Second');
      expect(c.targets, isEmpty);
      expect(c.groups.single.id, 'added');
      expect(c.plan!.paths.keys.toSet().containsAll(ids), isTrue);
      expect(c.plan!.spent, lessThanOrEqualTo(10));
    },
  );

  test(
    'bundled Harmony, Beer and Milk Tea expand independently and share Wheat',
    () async {
      final bundle = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final recipes = <String, Recipe>{};
      for (final mode in [bundle.alchemy, bundle.cooking, bundle.processing]) {
        for (final r in mode.items.values) {
          if (r.isCraftable || recipes[r.name]?.isCraftable != true) {
            recipes[r.name] = r;
          }
        }
      }
      final catalog = RecipeWorkerCatalog(
        recipes,
        const PlannerAssembly().plannerRules(bundle.supportingData),
      );
      final c = RecipeWorkerController(
        catalogBuilder: () => catalog,
        loadMap: () async => BdoResourceMapDataset.fromJson(
          jsonDecode(
            File(
              'packages/bdo_map_core/assets/data/resource_map.json',
            ).readAsStringSync(),
          ),
        ),
        loadEconomics: () async => BdoWorkerEconomicsDataset.fromJson(
          jsonDecode(
            File(
              'packages/bdo_map_core/assets/data/worker_economics.json',
            ).readAsStringSync(),
          ),
        ),
        initial: BdoRecipeWorkerPreferences(
          targets: ['Harmony Draught', 'Beer', 'Milk Tea'],
          budget: 100,
        ),
        onSave: (_) {},
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.error, isNull);
      final shared = c.groups.singleWhere((g) => g.id == 'shared');
      expect(shared.demands.any((d) => d.name == 'Wheat'), isTrue);
      expect(c.demands.where((d) => d.name == 'Wheat').length, 1);
      final wheat =
          catalog
              .expand('Beer')
              .singleWhere((l) => l.name == 'Wheat')
              .quantity +
          catalog
              .expand('Milk Tea')
              .singleWhere((l) => l.name == 'Wheat')
              .quantity;
      expect(c.demands.singleWhere((d) => d.name == 'Wheat').quantity, wheat);
      expect(c.leaves.any((l) => l.name == 'Bottle of River Water'), isFalse);
      expect(c.demands.any((d) => d.name == 'Mineral Water'), isFalse);
      expect(c.plan!.spent, lessThanOrEqualTo(100));
    },
  );
}
