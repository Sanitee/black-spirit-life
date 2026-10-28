import 'dart:convert';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_catalog.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/recipe_worker_controller.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'recipe_worker_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'NPC water stops only intermediate expansion; explicit Filtering remains',
    () {
      final catalog = RecipeWorkerCatalog({
        'Target': workerRecipe('Target', {'Purified Water': 3, 'Part': 2}),
        'Part': workerRecipe('Part', {'Purified Water': 1}),
        'Purified Water': workerRecipe('Purified Water', {
          'Bottle of River Water': 1,
        }),
      }, PlannerRules(npcPurchasePrices: {'Purified Water': 5000}));
      final leaves = catalog.expand('Target');
      expect(leaves.map((l) => l.name), ['Purified Water']);
      expect(leaves.single.quantity, 5);
      expect(leaves.single.vendor, isTrue);
      expect(
        catalog.expand('Purified Water').single.name,
        'Bottle of River Water',
      );
      expect(catalog.expand('Purified Water').single.vendor, isFalse);
    },
  );

  test(
    'extras share full route CP, fail without mutation, and survive Auto/reload',
    () async {
      BdoRecipeWorkerPreferences? saved;
      RecipeWorkerController make(BdoRecipeWorkerPreferences initial) =>
          RecipeWorkerController(
            catalogBuilder: workerCatalog,
            loadMap: () async => workerMap(),
            loadEconomics: () async => workerEconomics(),
            initial: initial,
            onSave: (v) => saved = v,
          );
      final c = make(BdoRecipeWorkerPreferences(target: 'Other', budget: 4));
      await c.load();
      expect(c.plan!.spent, 4);
      final before = c.plan!.paths.keys.toList();
      expect(await c.addItem('B'), isFalse);
      expect(c.plan!.paths.keys, before);
      expect(c.extraResourceIds, isEmpty);
      await c.adjust('A', add: false);
      expect(await c.addItem('B'), isTrue);
      expect(c.plan!.spent, 4);
      expect(c.plan!.nodesFor('extra:B'), hasLength(1));
      final manual = c.manualNodeIds.toSet();
      expect(manual, hasLength(1));
      await c.reset();
      expect(c.plan!.paths.keys, containsAll(manual));
      expect(c.plan!.nodesFor('extra:B'), hasLength(1));
      expect(c.plan!.remaining, 0);
      c.toggleInvested('bridge');
      final persisted = BdoRecipeWorkerPreferences.fromJson(
        jsonDecode(jsonEncode(saved!.toJson())),
      );
      expect(persisted.sameValuesAs(saved!), isTrue);
      final restored = make(persisted);
      await restored.load();
      expect(restored.plan!.paths.keys.toList(), c.plan!.paths.keys.toList());
      expect(restored.manualNodeIds, manual);
      expect(restored.investedNodeIds, {'bridge'});
      await restored.setBudget(2);
      expect(restored.plan!.spent, 0);
      expect(restored.plan!.remaining, 2);
      expect(restored.manualNodeIds, isEmpty);
      restored.dispose();
      c.dispose();
    },
  );

  test(
    'investment list deduplicates connections; checks do not change CP',
    () async {
      final c = RecipeWorkerController(
        catalogBuilder: workerCatalog,
        loadMap: () async => workerMap(),
        loadEconomics: () async => workerEconomics(),
        initial: BdoRecipeWorkerPreferences(target: 'Target', budget: 8),
        onSave: (_) {},
      );
      await c.load();
      final ids = c.investmentNodes.map((n) => n.id).toList();
      expect(ids.first, 'bridge');
      expect(ids.where((id) => id == 'bridge'), hasLength(1));
      expect(ids, isNot(contains('root')));
      expect(ids.length, c.plan!.paths.length + 1);
      c.toggleInvested('bridge');
      c.toggleInvested('not-in-the-plan');
      expect(c.investedNodeIds, {'bridge'});
      expect(c.plan!.spent, 8);
      c.showPage(RecipeWorkerPage.nodes);
      expect(c.pageTitle, 'Invest nodes');
      expect(c.back(), isTrue);
      expect(c.page, RecipeWorkerPage.recipe);
      expect(c.back(), isFalse);
      c.dispose();
    },
  );
}
