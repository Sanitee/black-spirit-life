import '../models/catalog_models.dart';
import '../models/craft_mode.dart';
import 'ingredient_quality.dart';
import 'mastery_yields.dart';
import 'planner_models.dart';
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
}

final class _PlannerContext {
  _PlannerContext({
    required this.mode,
    required Map<String, Recipe> recipes,
    required this.state,
    required this.rules,
  }) : items = _RecipeIndex(recipes, state.recipeVariantChoices);

  final CraftMode mode;
  final _RecipeIndex items;
  final PlannerState state;
  final PlannerRules rules;

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
                ? 0.0
                : _numberFor(state.inventory, name)
          : _haveFor(name);
      final completed = _setContains(state.completedSteps, name);
      final net = completed ? 0.0 : _nonNegative(gross - have);
      netNeed[folded] = net;

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

      for (final ingredient in recipe.ingredients) {
        final selected = _ingredientSelection(name, ingredient, count);
        if (selected.options.length > 1) {
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
                ? 0.0
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
      final selected = _ingredientSelection(name, ingredient, count);
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
      final recipe = items[name];
      if (recipe != null && _isCraftable(name)) {
        for (final ingredient in recipe.ingredients) {
          final selected = _ingredientSelection(name, ingredient, 1);
          visit(selected.key, level + 1);
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
    double multiplier,
  ) {
    final substitute = _preferredSubstitute(parentName, ingredient, multiplier);
    final ratio = _substituteRatio(ingredient, substitute);
    final quality = _qualitySelection(
      parentName: parentName,
      name: substitute,
      quantity: ingredient.quantity * multiplier * ratio,
      originalName: ingredient.name,
    );
    return _IngredientPick(
      key: quality.name,
      name: quality.name,
      quantity: quality.quantity,
      original: ingredient.name,
      baseName: substitute,
      grade: quality.grade,
      options: _substituteOptions(ingredient),
    );
  }

  String _preferredSubstitute(
    String parentName,
    Ingredient ingredient,
    double multiplier,
  ) {
    final options = _substituteOptions(ingredient);
    if (options.isEmpty) {
      return ingredient.name;
    }

    final choiceKey =
        'recipe:$parentName:${ingredient.substituteGroup ?? ingredient.name}';
    final saved = _stringFor(state.substituteChoices, choiceKey);
    if (saved != null && _containsName(options, saved)) {
      return _matchingName(options, saved)!;
    }

    final evaluated = options
        .map((option) {
          final selected = _qualitySelection(
            parentName: parentName,
            name: option,
            quantity:
                ingredient.quantity *
                multiplier *
                _substituteRatio(ingredient, option),
            originalName: ingredient.name,
          );
          final price = _priceFor(selected.name);
          final have = _haveFor(selected.name);
          final missing = selected.quantity > have
              ? selected.quantity - have
              : 0.0;
          return _EvaluatedOption(
            name: option,
            have: have,
            need: selected.quantity,
            missing: missing,
            price: price,
            stockKnown: _mapContains(state.marketStock, selected.name),
            stock: _stockFor(selected.name),
            total: price > 0 ? price * missing : double.infinity,
          );
        })
        .toList(growable: false);

    for (final option in evaluated) {
      if (option.need > 0 && option.have >= option.need) {
        return option.name;
      }
    }

    _EvaluatedOption? cheapestFullyStocked;
    for (final option in evaluated) {
      if (option.price <= 0 ||
          !option.stockKnown ||
          option.stock < option.missing) {
        continue;
      }
      if (cheapestFullyStocked == null ||
          option.total < cheapestFullyStocked.total) {
        cheapestFullyStocked = option;
      }
    }
    if (cheapestFullyStocked != null) {
      return cheapestFullyStocked.name;
    }

    _EvaluatedOption? cheapestUnknownStock;
    for (final option in evaluated) {
      if (option.price <= 0 || option.stockKnown) {
        continue;
      }
      if (cheapestUnknownStock == null ||
          option.total < cheapestUnknownStock.total) {
        cheapestUnknownStock = option;
      }
    }
    if (cheapestUnknownStock != null) {
      return cheapestUnknownStock.name;
    }

    _EvaluatedOption? bestPartialStock;
    for (final option in evaluated) {
      if (option.price <= 0 ||
          !option.stockKnown ||
          option.stock <= 0 ||
          option.missing <= 0) {
        continue;
      }
      if (bestPartialStock == null ||
          option.stockCoverage > bestPartialStock.stockCoverage ||
          (option.stockCoverage == bestPartialStock.stockCoverage &&
              option.total < bestPartialStock.total)) {
        bestPartialStock = option;
      }
    }
    if (bestPartialStock != null) {
      return bestPartialStock.name;
    }

    _EvaluatedOption? mostOwned;
    for (final option in evaluated) {
      if (option.have <= 0) {
        continue;
      }
      if (mostOwned == null || option.have > mostOwned.have) {
        mostOwned = option;
      }
    }
    if (mostOwned != null) {
      return mostOwned.name;
    }

    return _matchingName(options, ingredient.name) ?? options.first;
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

  _QualityPick _qualitySelection({
    required String parentName,
    required String name,
    required double quantity,
    required String originalName,
  }) {
    final grade = _selectedGrade(parentName, name, originalName);
    final amount = _nonNegative(quantity);

    for (final alternative in ingredientQualityAlternatives(
      rules: rules,
      ingredientName: name,
    )) {
      if (alternative.grade == grade) {
        return _QualityPick(
          name: alternative.name,
          quantity: alternative.requiredQuantityFor(amount),
          grade: alternative.grade,
        );
      }
    }
    return _QualityPick(name: name, quantity: amount, grade: 'normal');
  }

  String _selectedGrade(String parentName, String name, String originalName) {
    final parent = items[parentName];
    return selectedIngredientQualityGrade(
      rules: rules,
      parentIsProcessing: parent?.type.trim().toLowerCase() == 'processing',
      parentName: parentName,
      originalIngredientName: originalName,
      selectedIngredientName: name,
      savedGrades: state.ingredientGrades,
    );
  }

  double _outputPerCraft(Recipe recipe) =>
      const PlannerEngine().outputPerCraft(recipe: recipe, state: state);

  bool _isCraftable(String name) {
    final recipe = items[name];
    return recipe?.isCraftable ?? false;
  }

  double _haveFor(String name) =>
      state.ignoreIngredientInventory ? 0 : _numberFor(state.inventory, name);

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
    final recipeId = items[name]?.marketId;
    final configuredId = _stringFor(rules.marketIds, name);
    return (recipeId != null && recipeId.trim().isNotEmpty) ||
        (configuredId != null && configuredId.trim().isNotEmpty);
  }

  MarketMaterialState _materialMarketState(String name, double missing) {
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
    final price = npcBuyable
        ? npcPrice
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
    final pricedUnits = npcBuyable || (marketable && !stockKnown)
        ? missing
        : buyable;
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
      total: pricedUnits * price,
      status: status,
      hasSourceInfo: hasSource,
      stockKnown: !marketable || stockKnown,
    );
  }
}

final class _RecipeIndex {
  _RecipeIndex(
    Map<String, Recipe> recipes,
    Map<String, String> recipeVariantChoices,
  ) {
    for (final entry in recipes.entries) {
      final folded = _fold(entry.key);
      final existing = _names[folded];
      if (existing != null && existing != entry.key) {
        throw ArgumentError(
          'Case-insensitive recipe collision: "$existing" and "${entry.key}".',
        );
      }
      _names[folded] = entry.key;
      _recipes[folded] = entry.value.resolveVariant(
        _stringFor(recipeVariantChoices, entry.key),
      );
    }
  }

  final Map<String, String> _names = <String, String>{};
  final Map<String, Recipe> _recipes = <String, Recipe>{};

  Iterable<String> get names => _names.values;

  bool contains(String name) => _recipes.containsKey(_fold(name));

  Recipe? operator [](String name) => _recipes[_fold(name)];
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

final class _QualityPick {
  const _QualityPick({
    required this.name,
    required this.quantity,
    required this.grade,
  });

  final String name;
  final double quantity;
  final String grade;
}

final class _EvaluatedOption {
  const _EvaluatedOption({
    required this.name,
    required this.have,
    required this.need,
    required this.missing,
    required this.price,
    required this.stockKnown,
    required this.stock,
    required this.total,
  });

  final String name;
  final double have;
  final double need;
  final double missing;
  final double price;
  final bool stockKnown;
  final double stock;
  final double total;

  double get stockCoverage => stock / missing;
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

String? _matchingName(Iterable<String> values, String name) {
  for (final value in values) {
    if (_isSameName(value, name)) {
      return value;
    }
  }
  return null;
}

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
