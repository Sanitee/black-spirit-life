import '../catalog/temporarily_archived_items.dart';
import '../models/catalog_models.dart';
import '../models/craft_mode.dart';
import 'ingredient_quality.dart';
import 'mastery_yields.dart';
import 'planner_models.dart';
import 'recipe_route_economics.dart';
import 'source_resolution.dart';

final class PlannerEngine {
  const PlannerEngine();

  PlanResult buildPlan({
    required CraftMode mode,
    required Map<String, Recipe> recipes,
    required PlannerState state,
    PlannerRules? rules,
    String? targetOverride,
    int? wantOverride,
  }) {
    final context = _PlannerContext(
      mode: mode,
      recipes: recipes,
      state: state,
      rules: rules ?? PlannerRules(),
    );
    return context.buildPlan(
      targetOverride: targetOverride,
      wantOverride: wantOverride,
    );
  }

  double outputPerCraft({required Recipe recipe, required PlannerState state}) {
    final baseOutput = effectiveBaseOutput(recipe.baseOutput);
    return switch (recipe.type) {
      'alchemy' =>
        baseOutput *
            alchemyExpectedOutput(
              state.alchemyMastery.toDouble(),
              recipe.outputMinimum ?? 1,
              recipe.outputMaximum ?? 4,
            ),
      'cooking' =>
        baseOutput *
            cookingExpectedOutput(
              state.cookingMastery.toDouble(),
              recipe.outputMinimum ?? 1,
              recipe.outputMaximum ?? 4,
            ),
      'processing' => processingOutputPerCraft(recipe: recipe),
      _ => baseOutput,
    };
  }

  String gradeChoiceKey(String parentName, String originalName) =>
      'recipe:$parentName:$originalName';

  String substituteChoiceKey(String parentName, Ingredient ingredient) =>
      'recipe:$parentName:${ingredient.substituteGroup ?? ingredient.name}';

  PlanStepIngredient previewIngredientSelection({
    required Map<String, Recipe> recipes,
    required PlannerState state,
    required String parentName,
    required Ingredient ingredient,
    PlannerRules? rules,
  }) {
    final context = _PlannerContext(
      mode: CraftMode.alchemy,
      recipes: recipes,
      state: state,
      rules: rules ?? PlannerRules(),
    );
    return context.previewIngredient(parentName, ingredient);
  }

  /// Reuses a recipe index for repeated ingredient previews of one formula.
  /// Inventory, grades and substitutes remain per-call inputs. Variant changes
  /// use the existing independent path rather than an incompatible index.
  PreparedIngredientPreview prepareIngredientPreview({
    required Map<String, Recipe> recipes,
    required PlannerState state,
    PlannerRules? rules,
  }) => PreparedIngredientPreview._(
    Map<String, Recipe>.unmodifiable(recipes),
    state,
    rules ?? PlannerRules(),
  );
}

final class PreparedIngredientPreview {
  PreparedIngredientPreview._(this._recipes, PlannerState state, this._rules)
    : _variants = state.recipeVariantChoices,
      _items = _RecipeIndex(_recipes, state, _rules, resolveLazily: true);

  final Map<String, Recipe> _recipes;
  final Map<String, String> _variants;
  final PlannerRules _rules;
  // Only previewIngredient is reachable here; it never mutates route/index
  // state. Full plan construction keeps its separate mutable route index.
  final _RecipeIndex _items;

  PlanStepIngredient preview({
    required PlannerState state,
    required String parentName,
    required Ingredient ingredient,
  }) {
    final variants = state.recipeVariantChoices;
    if (variants.length != _variants.length ||
        _variants.entries.any((entry) => variants[entry.key] != entry.value)) {
      return const PlannerEngine().previewIngredientSelection(
        recipes: _recipes,
        state: state,
        parentName: parentName,
        ingredient: ingredient,
        rules: _rules,
      );
    }
    return _PlannerContext.withItems(
      mode: CraftMode.alchemy,
      items: _items,
      state: state,
      rules: _rules,
    ).previewIngredient(parentName, ingredient);
  }
}

final class _PlannerContext {
  _PlannerContext({
    required this.mode,
    required Map<String, Recipe> recipes,
    required this.state,
    required this.rules,
  }) : items = _RecipeIndex(recipes, state, rules);

  _PlannerContext.withItems({
    required this.mode,
    required this.items,
    required this.state,
    required this.rules,
  });

  final CraftMode mode;
  final _RecipeIndex items;
  final PlannerState state;
  final PlannerRules rules;

  final Map<(String, Ingredient), _IngredientPick> _resolvedIngredients = {};
  final Map<String, double> _selectionCraftCounts = {};

  PlanResult buildPlan({String? targetOverride, int? wantOverride}) {
    final craftables = items.names.where(_isCraftable).toList()
      ..sort(_compareNames);
    final target =
        targetOverride != null &&
            targetOverride.trim().isNotEmpty &&
            items.contains(targetOverride)
        ? targetOverride
        : items.contains(state.target)
        ? state.target
        : craftables.isEmpty
        ? ''
        : craftables.first;
    final requested = wantOverride ?? state.want;
    final want = requested < 0 ? 0 : requested;

    if (target.trim().isEmpty) {
      return PlanResult.empty(target: '', want: want);
    }

    final orderData = _buildOrder(target);
    final demand = _NameTotals()..add(target, want.toDouble());
    final netNeed = <String, double>{};
    final crafts = <String, double>{};
    final produced = <String, double>{};
    final optionMeta = <String, ChoiceMeta>{};
    final reversed = orderData.order.reversed.toList(growable: false);

    for (final name in reversed) {
      final folded = _fold(name);
      final gross = demand.value(name);
      final have = _isSameName(name, target)
          ? state.ignoreTargetInventory
                ? _numberFor(state.craftedInventory, name)
                : _numberFor(state.inventory, name)
          : _haveFor(name);
      final completed = _setContains(state.completedSteps, name);
      final net = completed ? 0.0 : _nonNegative(gross - have);
      netNeed[folded] = net;

      items.resolveRoute(name, requestedOutput: net);
      final recipe = items[name];
      if (recipe == null || !_isCraftable(name)) {
        continue;
      }

      final each = _outputPerCraft(recipe);
      final count = net > 0 ? (net / each).ceilToDouble() : 0.0;
      crafts[folded] = count;
      produced[folded] = count * each;

      if (completed) {
        continue;
      }

      _selectionCraftCounts[folded] = count;
      for (final ingredient in recipe.ingredients) {
        final selected = _ingredientSelection(
          name,
          ingredient,
          count,
          allocated: demand,
        );
        _resolvedIngredients[(folded, ingredient)] = selected;
        if (selected.options.length > 1 && selected.quantity > 0) {
          optionMeta[_fold(selected.key)] = ChoiceMeta(
            parentName: name,
            original: ingredient.name,
            substituteGroup: ingredient.substituteGroup ?? ingredient.name,
            options: selected.options,
            baseName: selected.baseName,
          );
        }
        demand.add(selected.key, selected.quantity);
      }
    }

    for (final name in reversed) {
      final folded = _fold(name);
      final gross = demand.value(name);
      final have = _isSameName(name, target)
          ? state.ignoreTargetInventory
                ? _numberFor(state.craftedInventory, name)
                : _numberFor(state.inventory, name)
          : _haveFor(name);
      final net = _setContains(state.completedSteps, name)
          ? 0.0
          : _nonNegative(gross - have);
      netNeed[folded] = net;

      final recipe = items[name];
      if (recipe != null && _isCraftable(name)) {
        final each = _outputPerCraft(recipe);
        final count = net > 0 ? (net / each).ceilToDouble() : 0.0;
        crafts[folded] = count;
        produced[folded] = count * each;
      }
    }

    final stepNames = reversed.where((name) {
      return _isCraftable(name) && (crafts[_fold(name)] ?? 0) > 0;
    }).toList();
    stepNames.sort((left, right) {
      final depthComparison = (orderData.depth[_fold(right)] ?? 0).compareTo(
        orderData.depth[_fold(left)] ?? 0,
      );
      return depthComparison != 0
          ? depthComparison
          : _compareNames(left, right);
    });

    final steps = <PlanStep>[];
    for (var index = 0; index < stepNames.length; index += 1) {
      final name = stepNames[index];
      steps.add(
        _stepFrom(
          name: name,
          index: index,
          demand: demand,
          netNeed: netNeed,
          crafts: crafts,
          produced: produced,
          depth: orderData.depth,
        ),
      );
    }

    final missing = <MissingMaterial>[];
    for (final entry in demand.entries) {
      if (_isCraftable(entry.name)) {
        continue;
      }
      final have = _haveFor(entry.name);
      final stillMissing = _nonNegative(entry.value - have);
      if (stillMissing <= 0) {
        continue;
      }
      missing.add(
        MissingMaterial(
          name: entry.name,
          key: entry.name,
          category: _categoryOf(entry.name),
          need: entry.value,
          have: have,
          missing: stillMissing,
          choice: optionMeta[_fold(entry.name)],
          market: _materialMarketState(entry.name, stillMissing),
        ),
      );
    }
    missing.sort((left, right) {
      final quantityComparison = right.missing.compareTo(left.missing);
      return quantityComparison != 0
          ? quantityComparison
          : _compareNames(left.name, right.name);
    });

    return PlanResult(
      target: target,
      want: want,
      steps: steps,
      missing: missing,
      empty: false,
      routeSelections: items.routeSelections,
    );
  }

  PlanStepIngredient previewIngredient(
    String parentName,
    Ingredient ingredient,
  ) {
    final selected = _ingredientSelection(parentName, ingredient, 1);
    final have = _haveFor(selected.key);
    return PlanStepIngredient(
      key: selected.key,
      name: selected.name,
      original: ingredient.name,
      substituteGroup: ingredient.substituteGroup ?? ingredient.name,
      baseName: selected.baseName,
      grade: selected.grade,
      options: selected.options,
      parentName: parentName,
      need: selected.quantity,
      have: have,
      missing: _nonNegative(selected.quantity - have),
      craftable: _isCraftable(selected.key),
    );
  }

  PlanStep _stepFrom({
    required String name,
    required int index,
    required _NameTotals demand,
    required Map<String, double> netNeed,
    required Map<String, double> crafts,
    required Map<String, double> produced,
    required Map<String, int> depth,
  }) {
    final folded = _fold(name);
    final count = crafts[folded] ?? 0;
    final recipe = items[name]!;
    final ingredients = recipe.ingredients.map((ingredient) {
      final selected =
          (_selectionCraftCounts[folded] == count
              ? _resolvedIngredients[(folded, ingredient)]
              : null) ??
          _ingredientSelection(name, ingredient, count);
      final have = _haveFor(selected.key);
      return PlanStepIngredient(
        key: selected.key,
        name: selected.name,
        original: ingredient.name,
        substituteGroup: ingredient.substituteGroup ?? ingredient.name,
        baseName: selected.baseName,
        grade: selected.grade,
        options: selected.options,
        parentName: name,
        need: selected.quantity,
        have: have,
        missing: _nonNegative(selected.quantity - have),
        craftable: _isCraftable(selected.key),
      );
    }).toList();
    final batchSize = mode == CraftMode.processing && state.useMassProcessing
        ? massProcessingBatchSize(state.processingMastery)
        : 1;
    final batchCount = batchSize > 1
        ? massProcessingBatchCount(count, batchSize)
        : count;

    return PlanStep(
      name: name,
      index: index,
      count: count,
      batchCount: batchCount,
      batchSize: batchSize,
      produced: produced[folded] ?? 0,
      demand: demand.value(name),
      net: netNeed[folded] ?? 0,
      depth: depth[folded] ?? 0,
      ingredients: ingredients,
    );
  }

  _OrderData _buildOrder(String target) {
    final visiting = <String>{};
    final visited = <String>{};
    final order = <String>[];
    final depth = <String, int>{};

    void visit(String name, int level) {
      final folded = _fold(name);
      final previousDepth = depth[folded] ?? 0;
      depth[folded] = level > previousDepth ? level : previousDepth;
      if (visited.contains(folded) || visiting.contains(folded)) {
        return;
      }
      visiting.add(folded);
      items.resolveRoute(name);
      final recipe = items[name];
      if (recipe != null && _isCraftable(name)) {
        for (final ingredient in recipe.ingredients) {
          // Batch ownership and costs may select a different material from a
          // one-craft preview. Include its dependencies before propagating need.
          for (final candidate in _ingredientCandidates(name, ingredient, 1)) {
            visit(candidate.key, level + 1);
          }
        }
        // Equivalent routes exchange only leaf inputs. Include every candidate
        // before the demand pass so a price/ownership choice cannot leave the
        // newly selected material outside the dependency order.
        final comparison = items.routeFor(name);
        if (comparison != null) {
          for (final option in comparison.options) {
            visit(option.ingredientName, level + 1);
          }
        }
      }
      visiting.remove(folded);
      visited.add(folded);
      order.add(name);
    }

    visit(target, 0);
    return _OrderData(order: order, depth: depth);
  }

  _IngredientPick _ingredientSelection(
    String parentName,
    Ingredient ingredient,
    double multiplier, {
    _NameTotals? allocated,
  }) {
    final candidates = _ingredientCandidates(
      parentName,
      ingredient,
      multiplier,
    );
    final savedBase = _stringFor(
      state.substituteChoices,
      'recipe:$parentName:${ingredient.substituteGroup ?? ingredient.name}',
    );
    final hasPreference =
        savedBase != null ||
        candidates.any(
          (pick) =>
              _savedGrade(parentName, ingredient.name, pick.baseName) != null,
        );
    if (hasPreference) {
      final preferred = candidates.where((pick) {
        final grade = _savedGrade(parentName, ingredient.name, pick.baseName);
        return (savedBase == null || _isSameName(savedBase, pick.baseName)) &&
            (grade == null || grade == pick.grade);
      }).toList();
      if (preferred.isNotEmpty) {
        // A deliberate choice remains inspectable even when sold out. Only
        // automatic selection should replace it with a stocked alternative.
        // Restrict the candidates before resolving stock and prices. Explicit
        // previews (including Opportunities' option comparisons) need only the
        // chosen candidates, not a full pricing pass over every substitute.
        return _bestIngredient([
          for (final pick in preferred)
            _evaluateIngredient(pick, allocated: allocated),
        ]).pick;
      }
    }
    return _bestIngredient([
      for (final pick in candidates)
        _evaluateIngredient(pick, allocated: allocated),
    ]).pick;
  }

  List<_IngredientPick> _ingredientCandidates(
    String parentName,
    Ingredient ingredient,
    double multiplier,
  ) {
    final options = _substituteOptions(ingredient);
    final bases = options.isEmpty ? [ingredient.name] : options;
    final parentIsProcessing =
        items[parentName]?.type.trim().toLowerCase() == 'processing';
    final picks = <_IngredientPick>[];
    for (final base in bases) {
      final perCraft = _nonNegative(
        ingredient.quantity * _substituteRatio(ingredient, base),
      );
      final quantity = perCraft * multiplier;
      void add(String name, String grade, double amount) {
        if (grade != 'normal' &&
            (_isTemporarilyArchived(name) ||
                _containsName(rules.legacyUnavailableItems, name))) {
          return;
        }
        picks.add(
          _IngredientPick(
            key: name,
            name: name,
            quantity: amount,
            original: ingredient.name,
            baseName: base,
            grade: grade,
            options: options,
          ),
        );
      }

      add(base, 'normal', quantity);
      if (recipeHasAuthoritativeQualityVariants(parentName) ||
          ingredientQualityProfile(
                rules: rules,
                parentIsProcessing: parentIsProcessing,
                ingredientName: base,
              ).family ==
              IngredientQualityFamily.none) {
        continue;
      }
      for (final alternative in ingredientQualityAlternatives(
        rules: rules,
        ingredientName: base,
      )) {
        add(
          alternative.name,
          alternative.grade,
          alternative.requiredQuantityFor(perCraft) * multiplier,
        );
      }
    }
    return picks;
  }

  String? _savedGrade(String parentName, String originalName, String baseName) {
    if (recipeHasAuthoritativeQualityVariants(parentName)) return null;
    final grade =
        _stringFor(
          state.ingredientGrades,
          'recipe:$parentName:$originalName',
        ) ??
        _stringFor(state.ingredientGrades, baseName);
    if (grade == null || grade.trim().toLowerCase() == 'auto') return null;
    // Unsupported grades cannot match this base's enumerated candidates.
    // They must not make unrelated normal-grade substitutes look preferred.
    return normalizeIngredientQualityGrade(grade);
  }

  _EvaluatedOption _evaluateIngredient(
    _IngredientPick pick, {
    _NameTotals? allocated,
  }) {
    final have = _nonNegative(
      _haveFor(pick.name) - (allocated?.value(pick.name) ?? 0),
    );
    final missing = _nonNegative(pick.quantity - have);
    final market = _materialMarketState(pick.name, missing);
    final available = have > 0 || market.buyable > 0;
    final unknown =
        (market.marketable && !market.stockKnown) || _isCraftable(pick.name);
    return _EvaluatedOption(
      pick: pick,
      have: have,
      missing: missing,
      availability: missing <= 0
          ? 0
          : available
          ? 1
          : unknown
          ? 2
          : 3,
      // Compare the complete remaining investment, never just the few units
      // listed for sale. Otherwise zero stock misleadingly looks free.
      total: missing <= 0
          ? 0
          : market.price > 0
          ? market.price * missing
          : double.infinity,
    );
  }

  _EvaluatedOption _bestIngredient(List<_EvaluatedOption> options) {
    var best = options.first;
    for (final option in options.skip(1)) {
      final availability = option.availability.compareTo(best.availability);
      final cost = option.total.compareTo(best.total);
      if (availability < 0 ||
          (availability == 0 &&
              (cost < 0 ||
                  (cost == 0 && option.ownedCoverage > best.ownedCoverage)))) {
        best = option;
      }
    }
    return best;
  }

  List<String> _substituteOptions(Ingredient ingredient) {
    if (ingredient.options.isEmpty) {
      return const <String>[];
    }
    final unavailable = rules.legacyUnavailableItems.map(_fold).toSet();
    final seen = <String>{};
    final options = <String>[];
    for (final option in ingredient.options) {
      final folded = _fold(option);
      if (!items.contains(option) ||
          unavailable.contains(folded) ||
          _isTemporarilyArchived(option) ||
          !seen.add(folded)) {
        continue;
      }
      options.add(option);
    }
    return options;
  }

  double _substituteRatio(Ingredient ingredient, String name) {
    final value = _numberFor(ingredient.substituteRatios, name, fallback: 1);
    return value < 0.0001 ? 0.0001 : value;
  }

  double _outputPerCraft(Recipe recipe) =>
      const PlannerEngine().outputPerCraft(recipe: recipe, state: state);

  bool _isCraftable(String name) {
    final recipe = items[name];
    return recipe?.isCraftable ?? false;
  }

  double _haveFor(String name) => state.ignoreIngredientInventory
      ? _numberFor(state.craftedInventory, name)
      : _numberFor(state.inventory, name);

  String _categoryOf(String name) {
    final recipe = items[name];
    if (recipe?.group != null && recipe!.group!.trim().isNotEmpty) {
      return recipe.group!;
    }
    return (recipe?.hasRecordedRecipe ?? false) ? 'Crafted' : 'Base Items';
  }

  double _priceFor(String name) {
    if (!_isMarketable(name)) {
      return 0;
    }
    return _mapContains(state.marketPrices, name)
        ? _numberFor(state.marketPrices, name)
        : _numberFor(rules.fallbackMarketPrices, name);
  }

  double _stockFor(String name) =>
      _isMarketable(name) ? _numberFor(state.marketStock, name) : 0;

  bool _isMarketable(String name) {
    if (_isTemporarilyArchived(name)) return false;
    final recipeId = items[name]?.marketId;
    final configuredId = _stringFor(rules.marketIds, name);
    return (recipeId != null && recipeId.trim().isNotEmpty) ||
        (configuredId != null && configuredId.trim().isNotEmpty);
  }

  bool _isTemporarilyArchived(String name) => isTemporarilyArchivedItem(
    name,
    itemId: items[name]?.marketId ?? _stringFor(rules.marketIds, name),
  );

  MarketMaterialState _materialMarketState(String name, double missing) {
    if (_isTemporarilyArchived(name)) {
      return MarketMaterialState(
        marketable: false,
        stock: 0,
        price: 0,
        buyable: 0,
        unavailable: 0,
        total: 0,
        status: missing <= 0 ? 'covered' : 'none',
        hasSourceInfo: false,
        stockKnown: false,
      );
    }
    final recipe = items[name];
    final source = resolveSourceInfo(name: name, recipe: recipe, rules: rules);
    final hasSource = source.hasDetails;
    final npcPrice = source.npcPrice;
    final npcBuyable = npcPrice > 0;
    final marketable = _isMarketable(name) && !npcBuyable;
    final stockKnown = marketable && _mapContains(state.marketStock, name);
    final stock = marketable
        ? _stockFor(name)
        : npcBuyable
        ? missing
        : 0.0;
    final preorderPrice = _numberFor(state.marketPreorderPrices, name);
    final price = npcBuyable
        ? npcPrice
        : marketable && stockKnown && stock == 0 && preorderPrice > 0
        ? preorderPrice
        : marketable
        ? _priceFor(name)
        : 0.0;
    final buyable = npcBuyable
        ? missing
        : marketable && stockKnown
        ? (missing < stock ? missing : stock)
        : 0.0;
    final unavailable = marketable && stockKnown
        ? _nonNegative(missing - stock)
        : 0.0;
    final status = missing <= 0
        ? 'covered'
        : npcBuyable
        ? 'vendor'
        : !marketable
        ? hasSource
              ? 'vendor'
              : 'none'
        : !stockKnown && price > 0
        ? 'priced'
        : stock >= missing
        ? 'ready'
        : stock > 0
        ? 'partial'
        : 'none';
    return MarketMaterialState(
      marketable: marketable,
      stock: stock,
      price: price,
      buyable: buyable,
      unavailable: marketable ? unavailable : 0,
      // Budget the whole remaining requirement, including unfilled preorders.
      // Stock still controls availability, not how much crafting will cost.
      total: missing * price,
      status: status,
      hasSourceInfo: hasSource,
      stockKnown: !marketable || stockKnown,
    );
  }
}

final class _RecipeIndex {
  _RecipeIndex(
    Map<String, Recipe> recipes,
    this.state,
    this.rules, {
    bool resolveLazily = false,
  }) : definitions = recipes {
    for (final entry in recipes.entries) {
      final folded = _fold(entry.key);
      final existing = _names[folded];
      if (existing != null && existing != entry.key) {
        throw ArgumentError(
          'Case-insensitive recipe collision: "$existing" and "${entry.key}".',
        );
      }
      _names[folded] = entry.key;
      // A direct ingredient preview touches only a handful of definitions.
      // Full plans retain eager resolution and their independent route state.
      if (!resolveLazily) {
        _recipes[folded] = entry.value.resolveVariant(
          _stringFor(state.recipeVariantChoices, entry.key),
        );
      }
    }
  }

  final Map<String, String> _names = <String, String>{};
  final Map<String, Recipe> _recipes = <String, Recipe>{};
  final Map<String, Recipe> definitions;
  final PlannerState state;
  final PlannerRules rules;
  final Map<String, RecipeRouteSelection> routeSelections =
      <String, RecipeRouteSelection>{};

  RecipeRouteSelection? routeFor(String name) =>
      routeSelections[_names[_fold(name)]];

  void resolveRoute(String name, {double? requestedOutput}) {
    final canonical = _names[_fold(name)];
    final definition = definitions[canonical];
    if (definition == null || !definition.hasRecipeVariants) return;
    final selection = resolveRecipeRoute(
      recipe: definition,
      recipes: definitions,
      state: state,
      rules: rules,
      requestedOutput: requestedOutput,
    );
    _recipes[_fold(name)] = definition.resolveVariant(
      selection.selectedVariantId,
    );
    if (selection.hasComparison) routeSelections[canonical!] = selection;
  }

  Iterable<String> get names => _names.values;

  bool contains(String name) => _names.containsKey(_fold(name));

  Recipe? operator [](String name) {
    final folded = _fold(name);
    final cached = _recipes[folded];
    if (cached != null) return cached;
    final canonical = _names[folded];
    if (canonical == null) return null;
    return _recipes[folded] = definitions[canonical]!.resolveVariant(
      _stringFor(state.recipeVariantChoices, canonical),
    );
  }
}

final class _NameTotals {
  final Map<String, _NamedTotal> _values = <String, _NamedTotal>{};

  void add(String name, double quantity) {
    if (quantity <= 0 || name.trim().isEmpty) {
      return;
    }
    final folded = _fold(name);
    final existing = _values[folded];
    _values[folded] = _NamedTotal(
      name: existing?.name ?? name,
      value: (existing?.value ?? 0) + quantity,
    );
  }

  double value(String name) => _values[_fold(name)]?.value ?? 0;

  Iterable<_NamedTotal> get entries => _values.values;
}

final class _NamedTotal {
  const _NamedTotal({required this.name, required this.value});

  final String name;
  final double value;
}

final class _OrderData {
  const _OrderData({required this.order, required this.depth});

  final List<String> order;
  final Map<String, int> depth;
}

final class _IngredientPick {
  const _IngredientPick({
    required this.key,
    required this.name,
    required this.quantity,
    required this.original,
    required this.baseName,
    required this.grade,
    required this.options,
  });

  final String key;
  final String name;
  final double quantity;
  final String original;
  final String baseName;
  final String grade;
  final List<String> options;
}

final class _EvaluatedOption {
  const _EvaluatedOption({
    required this.pick,
    required this.have,
    required this.missing,
    required this.availability,
    required this.total,
  });
  final _IngredientPick pick;
  final double have;
  final double missing;
  final int availability;
  final double total;
  double get ownedCoverage => pick.quantity <= 0
      ? 0
      : (have >= pick.quantity ? 1 : have / pick.quantity);
}

String _fold(String value) => value.toLowerCase();

bool _isSameName(String left, String right) => _fold(left) == _fold(right);

double _nonNegative(double value) => value < 0 ? 0 : value;

int _compareNames(String left, String right) {
  final foldedComparison = _fold(left).compareTo(_fold(right));
  return foldedComparison != 0 ? foldedComparison : left.compareTo(right);
}

bool _containsName(Iterable<String> values, String name) =>
    values.any((value) => _isSameName(value, name));

bool _setContains(Set<String> values, String key) =>
    values.any((value) => _isSameName(value, key));

bool _mapContains<T>(Map<String, T> values, String key) =>
    values.keys.any((value) => _isSameName(value, key));

T? _valueFor<T>(Map<String, T> values, String key) {
  for (final entry in values.entries) {
    if (_isSameName(entry.key, key)) {
      return entry.value;
    }
  }
  return null;
}

String? _stringFor(Map<String, String> values, String key) =>
    _valueFor(values, key);

double _numberFor(
  Map<String, double> values,
  String key, {
  double fallback = 0,
}) {
  final value = _valueFor(values, key);
  if (value == null) {
    return fallback;
  }
  if (!value.isFinite) {
    throw ArgumentError.value(value, key, 'numeric maps must be finite');
  }
  return value;
}
