import '../catalog/temporarily_archived_items.dart';
import '../models/catalog_models.dart';
import '../models/craft_mode.dart';

/// Relative preparation effort, not an EXP estimate or a crafting-time total.
final class RecipeEffort implements Comparable<RecipeEffort> {
  const RecipeEffort({required this.depth, required this.craftedBranches})
    : assert(depth >= 0),
      assert(craftedBranches >= 0);

  /// The longest chain in the simplest recorded ordinary production route.
  final int depth;

  /// Distinct crafted ingredients in that chain, excluding the final product.
  final int craftedBranches;

  @override
  int compareTo(RecipeEffort other) {
    final byDepth = depth.compareTo(other.depth);
    return byDepth != 0
        ? byDepth
        : craftedBranches.compareTo(other.craftedBranches);
  }

  @override
  bool operator ==(Object other) =>
      other is RecipeEffort &&
      depth == other.depth &&
      craftedBranches == other.craftedBranches;

  @override
  int get hashCode => Object.hash(depth, craftedBranches);
}

/// A reusable, state-independent index for sorting recipes without known EXP.
///
/// Supply all three modes so Processing can follow draughts into their Alchemy
/// ingredients. Ordinary routes and substitutes use the simplest recorded
/// preparation; batch quantities, prices, inventory and mastery do not inflate
/// it. Missing formulas give a lower bound, not proof an ingredient is raw.
/// Rebuild the index when its recipe snapshot or availability policy changes.
final class RecipeEffortIndex {
  RecipeEffortIndex(
    Map<CraftMode, Map<String, Recipe>> recipes, {
    Iterable<String> legacyUnavailableItems = const <String>[],
    bool Function(Recipe recipe, CraftMode mode)? isUnavailable,
  }) : _legacyUnavailableItems = legacyUnavailableItems.map(_fold).toSet() {
    for (final mode in CraftMode.values) {
      final definitions = recipes[mode]?.values.toSet().toList() ?? <Recipe>[];
      definitions.sort((a, b) => a.name.compareTo(b.name));
      for (final recipe in definitions) {
        final available =
            !_legacyUnavailableItems.contains(_fold(recipe.name)) &&
            !isTemporarilyArchivedItem(recipe.name, itemId: recipe.marketId) &&
            !(isUnavailable?.call(recipe, mode) ?? false);
        final definition = _Definition(recipe, mode, available);
        (_byName[_fold(recipe.name)] ??= []).add(definition);
        if (available && recipe.isCraftable) {
          final node = _EffortNode(definition);
          definition.node = node;
          _nodes.add(node);
        }
      }
    }
    for (final node in _nodes) {
      node.formulas = _ordinaryFormulas(
        node.definition.recipe,
      ).map(_inputsFor).whereType<List<_InputChoices>>().toList();
    }
    _resolveDepths();
  }

  static const _noCraft = RecipeEffort(depth: 0, craftedBranches: 0);
  static const _oneAction = RecipeEffort(depth: 1, craftedBranches: 0);
  final Set<String> _legacyUnavailableItems;
  final Map<String, List<_Definition>> _byName = {};
  final List<_EffortNode> _nodes = [];
  final Map<_EffortNode, int> _depths = {};
  final Map<_EffortNode, _EffortProfile> _profiles = {};
  final Map<(_EffortNode, String), RecipeEffort> _routeEfforts = {};

  RecipeEffort effortFor(Recipe recipe, CraftMode mode) {
    final definitions = _definitionsFor(
      recipe.name,
    ).where((definition) => definition.mode == mode).toList();
    final definition = definitions
        .where((definition) => identical(definition.recipe, recipe))
        .firstOrNull;
    final match = definition ?? definitions.firstOrNull;
    if (match == null) {
      return recipe.isCraftable &&
              !_legacyUnavailableItems.contains(_fold(recipe.name)) &&
              !isTemporarilyArchivedItem(recipe.name, itemId: recipe.marketId)
          ? _oneAction
          : _noCraft;
    }
    final node = match.node;
    if (node == null) return _noCraft;
    if (!identical(match.recipe, recipe)) {
      // resolveVariant keeps the original defaultVariantId. Match the active
      // formula itself so a selected route is not replaced by that default.
      final selected = recipe.variants
          .where((variant) => _matchesFormula(recipe, variant))
          .firstOrNull;
      if (selected != null) {
        final key = (node, _fold(selected.routeId));
        return _routeEfforts.putIfAbsent(key, () {
          final route = recipe.variantRouteById(selected.routeId)!;
          final formula = _inputsFor(_ordinaryVariant(route).ingredients);
          final depth = formula == null ? null : _formulaDepth(formula);
          if (formula == null || depth == null) return _oneAction;
          final profile = _formulaProfile(formula, depth, recipe.name);
          return profile.effort;
        });
      }
    }
    return _profileFor(node).effort;
  }

  List<_Definition> _definitionsFor(String name) {
    final definitions = _byName[_fold(name)] ?? const <_Definition>[];
    final exact = definitions
        .where((definition) => definition.recipe.name == name)
        .toList();
    return exact.isNotEmpty ? exact : definitions;
  }

  List<_InputChoices>? _inputsFor(List<Ingredient> ingredients) {
    if (ingredients.isEmpty) return null;
    final inputs = <_InputChoices>[];
    for (final ingredient in ingredients) {
      if (!ingredient.quantity.isFinite || ingredient.quantity <= 0) {
        return null;
      }
      var hasLeaf = false;
      final producers = <_EffortNode>{};
      final seen = <String>{};
      for (final name in [ingredient.name, ...ingredient.options]) {
        final folded = _fold(name);
        if (folded.isEmpty ||
            !seen.add(folded) ||
            _legacyUnavailableItems.contains(folded)) {
          continue;
        }
        final definitions = _definitionsFor(name);
        if (definitions.isEmpty) {
          // Unknown alternatives must not invent an easier route. The original
          // ingredient may be a valid material with no bundled formula yet.
          if (folded == _fold(ingredient.name) &&
              !isTemporarilyArchivedItem(name)) {
            hasLeaf = true;
          }
          continue;
        }
        final available = definitions.where(
          (definition) => definition.available,
        );
        final craftable = available
            .map((definition) => definition.node)
            .whereType<_EffortNode>()
            .toList();
        if (craftable.isNotEmpty) {
          producers.addAll(craftable);
        } else if (available.isNotEmpty) {
          hasLeaf = true;
        }
      }
      if (!hasLeaf && producers.isEmpty) return null;
      inputs.add(_InputChoices(hasLeaf, producers.toList()));
    }
    return inputs;
  }

  void _resolveDepths() {
    // Positive crafting steps mean a cycle cannot create a finite depth by
    // itself. Repeated relaxation also finds valid escapes from cyclic routes
    // without depending on traversal or query order.
    for (var pass = 0; pass < _nodes.length; pass++) {
      var changed = false;
      for (final node in _nodes) {
        for (final formula in node.formulas) {
          final depth = _formulaDepth(formula);
          if (depth != null &&
              (_depths[node] == null || depth < _depths[node]!)) {
            _depths[node] = depth;
            changed = true;
          }
        }
      }
      if (!changed) return;
    }
  }

  int? _inputDepth(_InputChoices input) {
    if (input.hasLeaf) return 0;
    int? best;
    for (final node in input.producers) {
      final depth = _depths[node];
      if (depth != null && (best == null || depth < best)) best = depth;
    }
    return best;
  }

  int? _formulaDepth(List<_InputChoices> formula) {
    var deepest = 0;
    for (final input in formula) {
      final depth = _inputDepth(input);
      if (depth == null) return null;
      if (depth > deepest) deepest = depth;
    }
    return deepest + 1;
  }

  _EffortProfile _profileFor(_EffortNode node) {
    final cached = _profiles[node];
    if (cached != null) return cached;
    final depth = _depths[node];
    if (depth == null) {
      // Cyclic or unavailable dependencies cannot establish a production
      // chain. Count only this action, not repeated trips around the cycle.
      return _profiles[node] = _EffortProfile(_oneAction, const {});
    }
    _EffortProfile? best;
    for (final formula in node.formulas) {
      if (_formulaDepth(formula) != depth) continue;
      final candidate = _formulaProfile(
        formula,
        depth,
        node.definition.recipe.name,
      );
      if (best == null || candidate.compareTo(best) < 0) best = candidate;
    }
    return _profiles[node] = best!;
  }

  _EffortProfile _formulaProfile(
    List<_InputChoices> formula,
    int depth,
    String productName,
  ) {
    final branches = <String>{};
    for (final input in formula) {
      if (input.hasLeaf) continue;
      final inputDepth = _inputDepth(input)!;
      _EffortProfile? bestInput;
      for (final child in input.producers) {
        if (_depths[child] != inputDepth) continue;
        // This is now a strict DAG: inputDepth < the parent's depth.
        final profile = _profileFor(child);
        final withChild = _EffortProfile(profile.effort, {
          ...profile.branches,
          _fold(child.definition.recipe.name),
        });
        if (bestInput == null || withChild.compareTo(bestInput) < 0) {
          bestInput = withChild;
        }
      }
      branches.addAll(bestInput!.branches);
    }
    // An explicitly selected conversion can close a loop through an otherwise
    // usable ordinary route. It must not gain effort by consuming itself.
    if (branches.contains(_fold(productName))) {
      return _EffortProfile(_oneAction, const {});
    }
    return _EffortProfile(
      RecipeEffort(depth: depth, craftedBranches: branches.length),
      branches,
    );
  }
}

Iterable<List<Ingredient>> _ordinaryFormulas(Recipe recipe) sync* {
  if (recipe.variants.isEmpty) {
    yield recipe.ingredients;
    return;
  }
  for (final route in recipe.variantRoutes) {
    yield _ordinaryVariant(route).ingredients;
  }
}

RecipeVariant _ordinaryVariant(RecipeVariantRoute route) {
  final variants = route.variants.toList()
    ..sort((a, b) {
      final byBatch = a.batchMultiplier.compareTo(b.batchMultiplier);
      return byBatch != 0 ? byBatch : a.id.compareTo(b.id);
    });
  return variants.first;
}

bool _matchesFormula(Recipe recipe, RecipeVariant variant) {
  if (recipe.type != variant.type ||
      recipe.method != variant.method ||
      recipe.baseOutput != variant.baseOutput ||
      recipe.ingredients.length != variant.ingredients.length) {
    return false;
  }
  for (var i = 0; i < recipe.ingredients.length; i++) {
    final actual = recipe.ingredients[i];
    final expected = variant.ingredients[i];
    if (actual.name != expected.name ||
        actual.quantity != expected.quantity ||
        actual.options.length != expected.options.length) {
      return false;
    }
    for (var option = 0; option < actual.options.length; option++) {
      if (actual.options[option] != expected.options[option]) return false;
    }
  }
  return true;
}

final class _Definition {
  _Definition(this.recipe, this.mode, this.available);
  final Recipe recipe;
  final CraftMode mode;
  final bool available;
  _EffortNode? node;
}

final class _EffortNode {
  _EffortNode(this.definition);
  final _Definition definition;
  late final List<List<_InputChoices>> formulas;
}

final class _InputChoices {
  const _InputChoices(this.hasLeaf, this.producers);
  final bool hasLeaf;
  final List<_EffortNode> producers;
}

final class _EffortProfile implements Comparable<_EffortProfile> {
  _EffortProfile(this.effort, Set<String> branches)
    : branches = Set.unmodifiable(branches),
      signature = (branches.toList()..sort()).join('\n');
  final RecipeEffort effort;
  final Set<String> branches;
  final String signature;

  @override
  int compareTo(_EffortProfile other) {
    final byEffort = effort.compareTo(other.effort);
    return byEffort != 0 ? byEffort : signature.compareTo(other.signature);
  }
}

String _fold(String value) => value.trim().toLowerCase();
