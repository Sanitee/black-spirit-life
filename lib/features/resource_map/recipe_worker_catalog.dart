import 'package:bdo_map_core/bdo_map_core.dart';

import '../../domain/models/catalog_models.dart';
import '../../domain/planner/planner_engine.dart';
import '../../domain/planner/planner_models.dart';

/// Fractional steady-state requirements for one final item. Rounding every
/// subrecipe to one craft would distort long-run node ratios. This projection
/// never reads the Craft Planner's target, inventory, completion or buy flags.
class RecipeWorkerLeaf {
  const RecipeWorkerLeaf(
    this.name,
    this.quantity,
    this.itemId,
    this.vendor,
    this.manual,
  );
  final String name;
  final double quantity;
  final int? itemId;
  final bool vendor;
  final bool manual;
}

class RecipeWorkerCatalog {
  RecipeWorkerCatalog(Map<String, Recipe> source, this.rules)
    : recipes = Map.unmodifiable(source),
      _byName = {for (final r in source.values) r.name.toLowerCase(): r};
  final Map<String, Recipe> recipes;
  final Map<String, Recipe> _byName;
  final PlannerRules rules;
  List<String> get targets =>
      recipes.values
          .where(
            (r) =>
                r.isCraftable && !rules.legacyUnavailableItems.contains(r.name),
          )
          .map((r) => r.name)
          .toSet()
          .toList()
        ..sort();

  List<RecipeWorkerLeaf> expand(String target) {
    final totals = <String, double>{};
    final names = <String, String>{};
    final stack = <String>{};
    final state = PlannerState(target: target);
    const engine = PlannerEngine();
    void visit(String name, double amount) {
      if (!amount.isFinite || amount <= 0) {
        throw StateError('Invalid recipe quantity');
      }
      final key = name.trim().toLowerCase();
      final recipe = _byName[key]?.resolveVariant(null);
      // The checklist purchases intermediate Purified Water. A deliberately
      // selected Filtering target still expands its recorded water recipe.
      final purchasedWater =
          key == 'purified water' &&
          stack.isNotEmpty &&
          _leaf(recipe?.name ?? name, amount).vendor;
      if (recipe == null || !recipe.isCraftable || purchasedWater) {
        totals.update(key, (v) => v + amount, ifAbsent: () => amount);
        names[key] = recipe?.name ?? name;
        return;
      }
      if (!stack.add(key)) throw StateError('Recipe cycle at $name');
      final output = engine.outputPerCraft(recipe: recipe, state: state);
      if (!output.isFinite || output <= 0) {
        throw StateError('Missing output for $name');
      }
      for (final ingredient in recipe.ingredients) {
        // Keep the recorded base formula, including its processing route.
        // Do not borrow a market/quality selection from an unrelated queue.
        visit(ingredient.name, amount * ingredient.quantity / output);
      }
      stack.remove(key);
    }

    if (!targets.contains(target)) throw ArgumentError.value(target, 'recipe');
    visit(target, 1);
    return [
      for (final key in totals.keys.toList()..sort())
        _leaf(names[key]!, totals[key]!),
    ];
  }

  /// One baseline final item per selected recipe; shared leaves add, rather
  /// than competing as duplicate demands. No inventory or worker stats enter.
  static List<RecipeWorkerLeaf> combine(
    Iterable<List<RecipeWorkerLeaf>> chains,
  ) {
    final totals = <String, RecipeWorkerLeaf>{};
    for (final chain in chains) {
      for (final leaf in chain) {
        final key = leaf.itemId == null
            ? leaf.name.toLowerCase()
            : 'item:${leaf.itemId}';
        final previous = totals[key];
        totals[key] = RecipeWorkerLeaf(
          previous?.name ?? leaf.name,
          (previous?.quantity ?? 0) + leaf.quantity,
          leaf.itemId,
          (previous?.vendor ?? false) || leaf.vendor,
          (previous?.manual ?? false) || leaf.manual,
        );
      }
    }
    return totals.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  RecipeWorkerLeaf _leaf(String name, double quantity) {
    final recipe = _byName[name.toLowerCase()];
    final acquisition = rules.acquisitionInfo[name];
    final routes = acquisition?.status == 'reviewed'
        ? acquisition!.routes.where((r) => r.isDisplayable).toList()
        : const <ItemAcquisitionRoute>[];
    final vendor =
        (recipe?.npcPrice ?? 0) > 0 ||
        (rules.npcPurchasePrices[name] ?? 0) > 0 ||
        (rules.vendorInfo[name]?.price ?? 0) > 0 ||
        routes.any((r) => r.kind == 'npc_vendor' || r.kind == 'npc_purchase');
    final manual = routes.any(
      (r) => {
        'gathering',
        'hunting',
        'manual_gathering',
        'field_gathering',
        'farming',
      }.contains(r.kind),
    );
    return RecipeWorkerLeaf(
      name,
      quantity,
      int.tryParse(recipe?.marketId ?? rules.marketIds[name] ?? ''),
      vendor,
      manual,
    );
  }

  static BdoResourceDefinition? resourceFor(
    RecipeWorkerLeaf leaf,
    BdoResourceMapDataset data,
  ) {
    final matches = data.resources
        .where(
          (r) =>
              (leaf.itemId != null && r.gameItemId == leaf.itemId) ||
              r.name.toLowerCase() == leaf.name.toLowerCase() ||
              r.aliases.any((s) => s.toLowerCase() == leaf.name.toLowerCase()),
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  static List<BdoWorkerRecipeDemand> workerDemands(
    List<RecipeWorkerLeaf> leaves,
    BdoResourceMapDataset data,
  ) => [
    for (final leaf in leaves)
      if (!leaf.vendor)
        if (resourceFor(leaf, data) case final resource?)
          if (data.workerNodesForResource(resource.id).isNotEmpty)
            BdoWorkerRecipeDemand(
              id: leaf.name,
              name: leaf.name,
              quantity: leaf.quantity,
              resourceUnits: {resource.id: 1},
            ),
  ];
}
