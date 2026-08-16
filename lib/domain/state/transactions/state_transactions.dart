import '../../models/craft_mode.dart';
import '../inventory_storage.dart';
import '../planner_state.dart';
import '../state_copy.dart';

class StateTransactionFailure implements Exception {
  const StateTransactionFailure(
    this.code,
    this.message, {
    this.conflicts = const [],
  });

  final String code;
  final String message;
  final List<String> conflicts;

  @override
  String toString() => 'StateTransactionFailure($code): $message';
}

class StateTransactionImpact {
  StateTransactionImpact({
    required this.operation,
    required Iterable<String> affectedReferences,
    Iterable<String> dependentRecipes = const [],
    Iterable<String> iconFilesEligibleForDeletion = const [],
    Iterable<String> sessionNamesToClear = const [],
  }) : affectedReferences = List<String>.unmodifiable(affectedReferences),
       dependentRecipes = List<String>.unmodifiable(dependentRecipes),
       iconFilesEligibleForDeletion = List<String>.unmodifiable(
         iconFilesEligibleForDeletion,
       ),
       sessionNamesToClear = List<String>.unmodifiable(sessionNamesToClear);

  final String operation;
  final List<String> affectedReferences;
  final List<String> dependentRecipes;
  final List<String> iconFilesEligibleForDeletion;
  final List<String> sessionNamesToClear;
}

class StateTransactionResult {
  const StateTransactionResult({required this.state, required this.impact});

  final PlannerState state;
  final StateTransactionImpact impact;
}

class CategoryTransactionResult {
  const CategoryTransactionResult({
    required this.state,
    required this.selectedCategory,
    required this.changed,
  });

  final PlannerState state;
  final String selectedCategory;
  final bool changed;
}

class PlannerStateTransactions {
  const PlannerStateTransactions();

  StateTransactionResult renameItem({
    required PlannerState state,
    required CraftMode mode,
    required String oldName,
    required String newName,
    required Iterable<String> existingItemNames,
    bool bundledItem = false,
    RecipeState? replacementRecipe,
  }) {
    final oldValue = oldName.trim();
    final newValue = newName.trim();
    if (oldValue.isEmpty || newValue.isEmpty) {
      throw const StateTransactionFailure(
        'blank-name',
        'Item names must not be blank.',
      );
    }
    final existing = existingItemNames.toList(growable: false);
    if (!existing.any((name) => _sameName(name, oldValue))) {
      throw StateTransactionFailure(
        'missing-item',
        'Item "$oldValue" does not exist.',
      );
    }
    final conflict = existing.where(
      (name) => _sameName(name, newValue) && !_sameName(name, oldValue),
    );
    if (conflict.isNotEmpty) {
      throw StateTransactionFailure(
        'name-collision',
        'Item "$newValue" conflicts with "${conflict.first}".',
        conflicts: conflict.toList(growable: false),
      );
    }

    final source = state.forMode(mode);
    final editEntry = _findEntry(source.recipeEdits, oldValue);
    final recipe = replacementRecipe ?? editEntry?.value;
    if (recipe == null) {
      throw StateTransactionFailure(
        'missing-recipe-edit',
        'A complete recipe edit is required to rename "$oldValue".',
      );
    }

    final affected = <String>[];
    final edits = <String, RecipeState?>{};
    for (final entry in source.recipeEdits.entries) {
      if (_sameName(entry.key, oldValue)) continue;
      edits[entry.key] = entry.value == null
          ? null
          : _renameRecipeReferences(entry.value!, oldValue, newValue, affected);
    }
    final renamedRecipe = _renameRecipeReferences(
      recipe,
      oldValue,
      newValue,
      affected,
    );
    if (bundledItem) {
      edits[oldValue] = null;
      affected.add('recipeEdits[$oldValue]=null');
    }
    edits[newValue] = renamedRecipe;
    affected.add('recipeEdits[$oldValue->$newValue]');

    final customIcons = _renameKey(
      source.customIcons,
      oldValue,
      newValue,
      'customIcons',
      affected,
    );
    final iconAliases = _renameStringMapKeysAndValues(
      source.iconAliases,
      oldValue,
      newValue,
      'iconAliases',
      affected,
    );
    final metadata = <String, IngredientMetadata>{};
    for (final entry in source.ingredientMeta.entries) {
      final key = _sameName(entry.key, oldValue) ? newValue : entry.key;
      final qualityBase = entry.value.qualityBase;
      metadata[key] = _sameNameNullable(qualityBase, oldValue)
          ? entry.value.copyWith(qualityBase: newValue)
          : entry.value;
      if (key != entry.key || metadata[key] != entry.value) {
        affected.add('ingredientMeta[${entry.key}]');
      }
    }

    final hidden = _renameNames(
      source.hiddenItems,
      oldValue,
      newValue,
      affected,
      'hiddenItems',
    );
    if (bundledItem && hidden.add(oldValue)) {
      affected.add('hiddenItems[$oldValue]');
    }
    final market = source.market.copyWith(
      prices: _renameKey(
        source.market.prices,
        oldValue,
        newValue,
        'market.prices',
        affected,
      ),
      stock: _renameKey(
        source.market.stock,
        oldValue,
        newValue,
        'market.stock',
        affected,
      ),
      tradeMarketIds: _renameKey(
        source.market.tradeMarketIds,
        oldValue,
        newValue,
        'market.tradeMarketIds',
        affected,
      ),
      totalTrades: _renameKey(
        source.market.totalTrades,
        oldValue,
        newValue,
        'market.totalTrades',
        affected,
      ),
      tradeObservedAt: _renameKey(
        source.market.tradeObservedAt,
        oldValue,
        newValue,
        'market.tradeObservedAt',
        affected,
      ),
      observedDailyTrades: _renameKey(
        source.market.observedDailyTrades,
        oldValue,
        newValue,
        'market.observedDailyTrades',
        affected,
      ),
      tradeObservationHours: _renameKey(
        source.market.tradeObservationHours,
        oldValue,
        newValue,
        'market.tradeObservationHours',
        affected,
      ),
      lastSoldAtEpochSeconds: _renameKey(
        source.market.lastSoldAtEpochSeconds,
        oldValue,
        newValue,
        'market.lastSoldAtEpochSeconds',
        affected,
      ),
      unlistedItemNames: _renameNames(
        source.market.unlistedItemNames,
        oldValue,
        newValue,
        affected,
        'market.unlistedItemNames',
      ),
      selected: _renameScalar(
        source.market.selected,
        oldValue,
        newValue,
        'market.selected',
        affected,
      ),
      search: _renameScalar(
        source.market.search,
        oldValue,
        newValue,
        'market.search',
        affected,
      ),
    );
    final compatibility = source.compatibility.copyWith(
      done: _renameKey(
        source.compatibility.done,
        oldValue,
        newValue,
        'compatibility.done',
        affected,
      ),
      planSearch: _renameScalar(
        source.compatibility.planSearch,
        oldValue,
        newValue,
        'compatibility.planSearch',
        affected,
      ),
    );
    final renamedMode = source.copyWith(
      target: _renameScalar(
        source.target,
        oldValue,
        newValue,
        'target',
        affected,
      ),
      bonusTarget: _renameScalar(
        source.bonusTarget,
        oldValue,
        newValue,
        'bonusTarget',
        affected,
      ),
      inventory: _renameKey(
        source.inventory,
        oldValue,
        newValue,
        'inventory',
        affected,
      ),
      recipeEdits: edits,
      customIcons: customIcons,
      iconAliases: iconAliases,
      ingredientMeta: metadata,
      substituteChoices: _renameChoiceMap(
        source.substituteChoices,
        oldValue,
        newValue,
        renameValues: true,
        affected: affected,
      ),
      ingredientGrades: _renameChoiceMap(
        source.ingredientGrades,
        oldValue,
        newValue,
        renameValues: false,
        affected: affected,
      ),
      recipeVariantChoices: _renameKey(
        source.recipeVariantChoices,
        oldValue,
        newValue,
        'recipeVariantChoices',
        affected,
      ),
      favoriteRecipes: _renameNames(
        source.favoriteRecipes,
        oldValue,
        newValue,
        affected,
        'favoriteRecipes',
      ),
      hiddenItems: hidden,
      market: market,
      completedSteps: _renameNames(
        source.completedSteps,
        oldValue,
        newValue,
        affected,
        'completedSteps',
      ),
      compatibility: compatibility,
    );
    final nextMode = InventoryStorageState.fromModeState(
      source,
    ).renameItem(oldValue, newValue).applyTo(renamedMode);
    return StateTransactionResult(
      state: _replaceMode(state, mode, nextMode),
      impact: StateTransactionImpact(
        operation: 'rename',
        affectedReferences: affected,
        sessionNamesToClear: [oldValue],
      ),
    );
  }

  StateTransactionResult deleteOrHideItem({
    required PlannerState state,
    required CraftMode mode,
    required String itemName,
    required bool bundledItem,
    required String fallbackTarget,
  }) {
    final name = itemName.trim();
    if (name.isEmpty) {
      throw const StateTransactionFailure(
        'blank-name',
        'Item name must not be blank.',
      );
    }
    final fallback = fallbackTarget.trim();
    if (fallback.isEmpty || _sameName(name, fallback)) {
      throw const StateTransactionFailure(
        'invalid-fallback',
        'The repair target must be non-blank and differ from the removed item.',
      );
    }
    final source = state.forMode(mode);
    final dependencies = _dependentUserRecipes(source, name);
    if (dependencies.isNotEmpty) {
      throw StateTransactionFailure(
        'dependent-recipes',
        'User recipes still depend on "$name".',
        conflicts: dependencies,
      );
    }

    final affected = <String>[];
    final edits = _removeKeys(
      source.recipeEdits,
      name,
      'recipeEdits',
      affected,
    );
    if (bundledItem) edits[name] = null;
    final removedIcon = _findEntry(source.customIcons, name)?.value;
    final icons = _removeKeys(
      source.customIcons,
      name,
      'customIcons',
      affected,
    );
    final aliases = <String, String>{};
    for (final entry in source.iconAliases.entries) {
      if (_sameName(entry.key, name) || _sameName(entry.value, name)) {
        affected.add('iconAliases[${entry.key}]');
      } else {
        aliases[entry.key] = entry.value;
      }
    }
    final metadata = <String, IngredientMetadata>{};
    for (final entry in source.ingredientMeta.entries) {
      if (_sameName(entry.key, name)) {
        affected.add('ingredientMeta[${entry.key}]');
        continue;
      }
      metadata[entry.key] = _sameNameNullable(entry.value.qualityBase, name)
          ? entry.value.copyWith(qualityBase: null)
          : entry.value;
    }
    final hidden = Set<String>.of(source.hiddenItems)
      ..removeWhere((value) => _sameName(value, name));
    if (bundledItem) hidden.add(name);
    final unlistedItemNames = source.market.unlistedItemNames
        .where((value) => !_sameName(value, name))
        .toSet();
    if (unlistedItemNames.length != source.market.unlistedItemNames.length) {
      affected.add('market.unlistedItemNames[$name]');
    }

    final market = source.market.copyWith(
      prices: _removeKeys(
        source.market.prices,
        name,
        'market.prices',
        affected,
      ),
      stock: _removeKeys(source.market.stock, name, 'market.stock', affected),
      tradeMarketIds: _removeKeys(
        source.market.tradeMarketIds,
        name,
        'market.tradeMarketIds',
        affected,
      ),
      totalTrades: _removeKeys(
        source.market.totalTrades,
        name,
        'market.totalTrades',
        affected,
      ),
      tradeObservedAt: _removeKeys(
        source.market.tradeObservedAt,
        name,
        'market.tradeObservedAt',
        affected,
      ),
      observedDailyTrades: _removeKeys(
        source.market.observedDailyTrades,
        name,
        'market.observedDailyTrades',
        affected,
      ),
      tradeObservationHours: _removeKeys(
        source.market.tradeObservationHours,
        name,
        'market.tradeObservationHours',
        affected,
      ),
      lastSoldAtEpochSeconds: _removeKeys(
        source.market.lastSoldAtEpochSeconds,
        name,
        'market.lastSoldAtEpochSeconds',
        affected,
      ),
      unlistedItemNames: unlistedItemNames,
      selected: _sameName(source.market.selected, name)
          ? fallback
          : source.market.selected,
      search: _sameName(source.market.search, name) ? '' : source.market.search,
    );
    final compatibility = source.compatibility.copyWith(
      done: _removeKeys(
        source.compatibility.done,
        name,
        'compatibility.done',
        affected,
      ),
      planSearch: _sameName(source.compatibility.planSearch, name)
          ? ''
          : source.compatibility.planSearch,
    );
    final removedMode = source.copyWith(
      target: _sameName(source.target, name) ? fallback : source.target,
      bonusTarget: _sameName(source.bonusTarget, name)
          ? fallback
          : source.bonusTarget,
      inventory: _removeKeys(source.inventory, name, 'inventory', affected),
      recipeEdits: edits,
      customIcons: icons,
      iconAliases: aliases,
      ingredientMeta: metadata,
      substituteChoices: _removeChoiceReferences(
        source.substituteChoices,
        name,
        removeMatchingValues: true,
        affected: affected,
      ),
      ingredientGrades: _removeChoiceReferences(
        source.ingredientGrades,
        name,
        removeMatchingValues: false,
        affected: affected,
      ),
      recipeVariantChoices: bundledItem
          ? source.recipeVariantChoices
          : _removeKeys(
              source.recipeVariantChoices,
              name,
              'recipeVariantChoices',
              affected,
            ),
      favoriteRecipes: source.favoriteRecipes.where(
        (value) => !_sameName(value, name),
      ),
      hiddenItems: hidden,
      market: market,
      completedSteps: source.completedSteps.where(
        (value) => !_sameName(value, name),
      ),
      compatibility: compatibility,
    );
    final nextMode = InventoryStorageState.fromModeState(
      source,
    ).removeItem(name).applyTo(removedMode);

    final nextState = _replaceMode(state, mode, nextMode);
    final iconDeletion = <String>[];
    if (removedIcon != null &&
        !_stateReferencesIcon(nextState, removedIcon.relativePath)) {
      iconDeletion.add(removedIcon.relativePath);
    }
    return StateTransactionResult(
      state: nextState,
      impact: StateTransactionImpact(
        operation: bundledItem ? 'hide-bundled' : 'delete-user',
        affectedReferences: affected,
        dependentRecipes: dependencies,
        iconFilesEligibleForDeletion: iconDeletion,
        sessionNamesToClear: [name],
      ),
    );
  }

  /// Hides an Inventory row without destroying the item definition that Data
  /// may later restore. Unlike editor/book deletion, Inventory's delete-tool
  /// affordance is a reversible visibility toggle for both bundled and
  /// user-authored items.
  StateTransactionResult hideInventoryItem({
    required PlannerState state,
    required CraftMode mode,
    required String itemName,
  }) {
    final name = itemName.trim();
    if (name.isEmpty) {
      throw const StateTransactionFailure(
        'blank-name',
        'Item name must not be blank.',
      );
    }

    final source = state.forMode(mode);
    final alreadyHidden = source.hiddenItems.any(
      (value) => _sameName(value, name),
    );
    final hidden = Set<String>.of(source.hiddenItems)
      ..removeWhere((value) => _sameName(value, name))
      ..add(name);
    final nextMode = source.copyWith(hiddenItems: hidden);
    return StateTransactionResult(
      state: _replaceMode(state, mode, nextMode),
      impact: StateTransactionImpact(
        operation: 'hide-inventory-item',
        affectedReferences: alreadyHidden
            ? const <String>[]
            : <String>['hiddenItems[$name]'],
        sessionNamesToClear: <String>[name],
      ),
    );
  }

  /// Hides a Recipe Book item while preserving its definition and editor data
  /// so it can be restored after the session-level Undo window has passed.
  StateTransactionResult hideRecipeBookItem({
    required PlannerState state,
    required CraftMode mode,
    required String itemName,
    required String fallbackTarget,
    Iterable<String> additionallyHiddenRecipes = const <String>[],
  }) {
    final name = itemName.trim();
    if (name.isEmpty) {
      throw const StateTransactionFailure(
        'blank-name',
        'Item name must not be blank.',
      );
    }
    final fallback = fallbackTarget.trim();
    if (fallback.isEmpty || _sameName(name, fallback)) {
      throw const StateTransactionFailure(
        'invalid-fallback',
        'The repair target must be non-blank and differ from the hidden item.',
      );
    }
    final source = state.forMode(mode);
    final ignoredDependencies = additionallyHiddenRecipes
        .map((value) => value.trim().toLowerCase())
        .toSet();
    final dependencies =
        _dependentUserRecipes(source, name, ignoreHiddenRecipes: true)
            .where(
              (dependent) =>
                  !ignoredDependencies.contains(dependent.trim().toLowerCase()),
            )
            .toList(growable: false);
    if (dependencies.isNotEmpty) {
      throw StateTransactionFailure(
        'dependent-recipes',
        'User recipes still depend on "$name".',
        conflicts: dependencies,
      );
    }

    final alreadyHidden = source.hiddenItems.any(
      (value) => _sameName(value, name),
    );
    final hidden = Set<String>.of(source.hiddenItems)
      ..removeWhere((value) => _sameName(value, name))
      ..add(name);
    final affected = <String>[
      if (!alreadyHidden) 'hiddenItems[$name]',
      if (_sameName(source.target, name)) 'target',
      if (_sameName(source.bonusTarget, name)) 'bonusTarget',
    ];
    final nextMode = source.copyWith(
      target: _sameName(source.target, name) ? fallback : source.target,
      bonusTarget: _sameName(source.bonusTarget, name)
          ? fallback
          : source.bonusTarget,
      hiddenItems: hidden,
    );
    return StateTransactionResult(
      state: _replaceMode(state, mode, nextMode),
      impact: StateTransactionImpact(
        operation: 'hide-recipe-book-item',
        affectedReferences: affected,
        dependentRecipes: dependencies,
        sessionNamesToClear: <String>[name],
      ),
    );
  }

  /// Restores hidden rows without disturbing their remaining user data.
  ///
  /// Older Recipe Book deletion builds stored both a hidden marker and a null
  /// recipe-edit tombstone for bundled recipes. Removing only the marker left
  /// those recipes absent, so restoration deliberately clears matching null
  /// tombstones as well.
  StateTransactionResult restoreHiddenItems({
    required PlannerState state,
    required CraftMode mode,
    Iterable<String>? itemNames,
  }) {
    final source = state.forMode(mode);
    String fold(String value) => value.trim().toLowerCase();

    final defaultNames = <String>[
      ...source.hiddenItems,
      for (final entry in source.recipeEdits.entries)
        if (entry.value == null) entry.key,
    ];
    final requested = (itemNames ?? defaultNames)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final foldedRequested = requested.map(fold).toSet();
    final affected = <String>[];
    final restoredNames = <String>{};

    final hidden = <String>{};
    for (final value in source.hiddenItems) {
      if (foldedRequested.contains(fold(value))) {
        affected.add('hiddenItems[$value]');
        restoredNames.add(value);
      } else {
        hidden.add(value);
      }
    }

    final edits = <String, RecipeState?>{};
    for (final entry in source.recipeEdits.entries) {
      if (entry.value == null && foldedRequested.contains(fold(entry.key))) {
        affected.add('recipeEdits[${entry.key}]');
        restoredNames.add(entry.key);
      } else {
        edits[entry.key] = entry.value;
      }
    }

    if (affected.isEmpty) {
      return StateTransactionResult(
        state: state,
        impact: StateTransactionImpact(
          operation: 'restore-hidden-items',
          affectedReferences: const <String>[],
        ),
      );
    }

    final sortedNames = restoredNames.toList()..sort(_compareNames);
    return StateTransactionResult(
      state: _replaceMode(
        state,
        mode,
        source.copyWith(hiddenItems: hidden, recipeEdits: edits),
      ),
      impact: StateTransactionImpact(
        operation: 'restore-hidden-items',
        affectedReferences: affected,
        sessionNamesToClear: sortedNames,
      ),
    );
  }

  CategoryTransactionResult addCategory({
    required PlannerState state,
    required CraftMode mode,
    required String category,
  }) {
    final value = category.trim();
    if (value.isEmpty) {
      throw const StateTransactionFailure(
        'blank-category',
        'Category must not be blank.',
      );
    }
    final source = state.forMode(mode);
    final existing = source.customCategories.where(
      (candidate) => _sameName(candidate, value),
    );
    if (existing.isNotEmpty) {
      return CategoryTransactionResult(
        state: state,
        selectedCategory: existing.first,
        changed: false,
      );
    }
    final categories = [...source.customCategories, value]..sort(_compareNames);
    return CategoryTransactionResult(
      state: _replaceMode(
        state,
        mode,
        source.copyWith(customCategories: categories),
      ),
      selectedCategory: value,
      changed: true,
    );
  }

  CategoryTransactionResult renameCategory({
    required PlannerState state,
    required CraftMode mode,
    required String oldCategory,
    required String newCategory,
  }) {
    final oldValue = oldCategory.trim();
    final newValue = newCategory.trim();
    if (oldValue.isEmpty || newValue.isEmpty) {
      throw const StateTransactionFailure(
        'blank-category',
        'Category must not be blank.',
      );
    }
    final source = state.forMode(mode);
    if (!source.customCategories.any((value) => _sameName(value, oldValue))) {
      throw StateTransactionFailure(
        'missing-category',
        'Custom category "$oldValue" does not exist.',
      );
    }
    final collision = source.customCategories.where(
      (value) => _sameName(value, newValue) && !_sameName(value, oldValue),
    );
    if (collision.isNotEmpty) {
      throw StateTransactionFailure(
        'category-collision',
        'Category "$newValue" conflicts with "${collision.first}".',
      );
    }
    final categories =
        source.customCategories
            .map((value) => _sameName(value, oldValue) ? newValue : value)
            .toList()
          ..sort(_compareNames);
    final metadata = {
      for (final entry in source.ingredientMeta.entries)
        entry.key: _sameNameNullable(entry.value.category, oldValue)
            ? entry.value.copyWith(category: newValue)
            : entry.value,
    };
    return CategoryTransactionResult(
      state: _replaceMode(
        state,
        mode,
        source.copyWith(customCategories: categories, ingredientMeta: metadata),
      ),
      selectedCategory: newValue,
      changed: oldValue != newValue || oldCategory != newCategory,
    );
  }

  StateTransactionResult resetCategoryOverrides({
    required PlannerState state,
    required CraftMode mode,
    required String category,
  }) {
    final value = category.trim();
    if (value.isEmpty) {
      throw const StateTransactionFailure(
        'blank-category',
        'Category must not be blank.',
      );
    }
    final source = state.forMode(mode);
    final affected = <String>[];
    final metadata = <String, IngredientMetadata>{};
    for (final entry in source.ingredientMeta.entries) {
      var next = entry.value;
      if (_sameNameNullable(next.category, value)) {
        next = next.copyWith(category: null);
        affected.add('ingredientMeta[${entry.key}].category');
      }
      if (!_metadataIsEmpty(next)) metadata[entry.key] = next;
    }
    return StateTransactionResult(
      state: _replaceMode(
        state,
        mode,
        source.copyWith(ingredientMeta: metadata),
      ),
      impact: StateTransactionImpact(
        operation: 'reset-category-overrides',
        affectedReferences: affected,
      ),
    );
  }
}

PlannerState _replaceMode(PlannerState state, CraftMode mode, ModeState value) {
  return switch (mode) {
    CraftMode.alchemy => state.copyWith(alchemy: value),
    CraftMode.cooking => state.copyWith(cooking: value),
    CraftMode.processing => state.copyWith(processing: value),
  };
}

RecipeState _renameRecipeReferences(
  RecipeState recipe,
  String oldName,
  String newName,
  List<String> affected,
) {
  var changed = false;
  final ingredients = <IngredientState>[];
  for (final ingredient in recipe.ingredients) {
    final name = _replaceName(ingredient.name, oldName, newName);
    final options = ingredient.options
        .map((value) => _replaceName(value, oldName, newName))
        .toList();
    final ratios = _renameKey(
      ingredient.substituteRatios,
      oldName,
      newName,
      'recipe.substituteRatios',
      affected,
    );
    if (name != ingredient.name ||
        !_sameOrderedValues(options, ingredient.options) ||
        !_sameMapKeys(ratios, ingredient.substituteRatios)) {
      changed = true;
    }
    ingredients.add(
      ingredient.copyWith(
        name: name,
        options: options,
        substituteRatios: ratios,
      ),
    );
  }
  return recipe.copyWith(
    ingredients: changed ? ingredients : recipe.ingredients,
  );
}

List<String> _dependentUserRecipes(
  ModeState state,
  String itemName, {
  bool ignoreHiddenRecipes = false,
}) {
  final result = <String>[];
  for (final entry in state.recipeEdits.entries) {
    if (_sameName(entry.key, itemName) || entry.value == null) continue;
    if (ignoreHiddenRecipes &&
        state.hiddenItems.any((name) => _sameName(name, entry.key))) {
      continue;
    }
    if (entry.value!.ingredients.any(
      (ingredient) =>
          _sameName(ingredient.name, itemName) ||
          ingredient.options.any((value) => _sameName(value, itemName)) ||
          ingredient.substituteRatios.keys.any(
            (value) => _sameName(value, itemName),
          ),
    )) {
      result.add(entry.key);
    }
  }
  result.sort(_compareNames);
  return result;
}

Map<String, T> _renameKey<T>(
  Map<String, T> source,
  String oldName,
  String newName,
  String label,
  List<String> affected,
) {
  final result = <String, T>{};
  for (final entry in source.entries) {
    final key = _sameName(entry.key, oldName) ? newName : entry.key;
    result[key] = entry.value;
    if (key != entry.key) affected.add('$label[${entry.key}]');
  }
  return result;
}

Map<String, T> _removeKeys<T>(
  Map<String, T> source,
  String name,
  String label,
  List<String> affected,
) {
  final result = <String, T>{};
  for (final entry in source.entries) {
    if (_sameName(entry.key, name)) {
      affected.add('$label[${entry.key}]');
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

Map<String, String> _renameStringMapKeysAndValues(
  Map<String, String> source,
  String oldName,
  String newName,
  String label,
  List<String> affected,
) {
  final result = <String, String>{};
  for (final entry in source.entries) {
    final key = _sameName(entry.key, oldName) ? newName : entry.key;
    final value = _replaceName(entry.value, oldName, newName);
    result[key] = value;
    if (key != entry.key || value != entry.value) {
      affected.add('$label[${entry.key}]');
    }
  }
  return result;
}

Map<String, String> _renameChoiceMap(
  Map<String, String> source,
  String oldName,
  String newName, {
  required bool renameValues,
  required List<String> affected,
}) {
  final result = <String, String>{};
  for (final entry in source.entries) {
    final key = _renameChoiceKey(entry.key, oldName, newName);
    final value = renameValues
        ? _replaceName(entry.value, oldName, newName)
        : entry.value;
    result[key] = value;
    if (key != entry.key || value != entry.value) {
      affected.add('choice[${entry.key}]');
    }
  }
  return result;
}

Map<String, String> _removeChoiceReferences(
  Map<String, String> source,
  String name, {
  required bool removeMatchingValues,
  required List<String> affected,
}) {
  final result = <String, String>{};
  for (final entry in source.entries) {
    final remove =
        _choiceKeyReferences(entry.key, name) ||
        (removeMatchingValues && _sameName(entry.value, name));
    if (remove) {
      affected.add('choice[${entry.key}]');
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

String _renameChoiceKey(String key, String oldName, String newName) {
  var result = key;
  final oldPrefix = 'recipe:$oldName:';
  if (result.toLowerCase().startsWith(oldPrefix.toLowerCase())) {
    result = 'recipe:$newName:${result.substring(oldPrefix.length)}';
  }
  final oldSuffix = ':$oldName';
  if (result.toLowerCase().endsWith(oldSuffix.toLowerCase())) {
    result =
        '${result.substring(0, result.length - oldSuffix.length)}:$newName';
  }
  return result;
}

bool _choiceKeyReferences(String key, String name) {
  final folded = key.toLowerCase();
  return folded.startsWith('recipe:${name.toLowerCase()}:') ||
      folded.endsWith(':${name.toLowerCase()}');
}

Set<String> _renameNames(
  Iterable<String> source,
  String oldName,
  String newName,
  List<String> affected,
  String label,
) {
  final result = <String>{};
  for (final value in source) {
    final next = _replaceName(value, oldName, newName);
    result.add(next);
    if (next != value) affected.add('$label[$value]');
  }
  return result;
}

MapEntry<String, T>? _findEntry<T>(Map<String, T> source, String name) {
  for (final entry in source.entries) {
    if (_sameName(entry.key, name)) return entry;
  }
  return null;
}

String _replaceName(String value, String oldName, String newName) =>
    _sameName(value, oldName) ? newName : value;

String _renameScalar(
  String value,
  String oldName,
  String newName,
  String label,
  List<String> affected,
) {
  final result = _replaceName(value, oldName, newName);
  if (result != value) affected.add(label);
  return result;
}

bool _stateReferencesIcon(PlannerState state, String relativePath) => CraftMode
    .values
    .map(state.forMode)
    .expand((mode) => mode.customIcons.values)
    .any((icon) => icon.relativePath == relativePath);

bool _sameName(String left, String right) =>
    left.toLowerCase() == right.toLowerCase();

bool _sameNameNullable(String? left, String right) =>
    left != null && _sameName(left, right);

int _compareNames(String left, String right) {
  final folded = left.toLowerCase().compareTo(right.toLowerCase());
  return folded != 0 ? folded : left.compareTo(right);
}

bool _sameOrderedValues(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameMapKeys(Map<String, Object?> left, Map<String, Object?> right) =>
    left.length == right.length && left.keys.every(right.containsKey);

bool _metadataIsEmpty(IngredientMetadata value) =>
    (value.category == null || value.category!.trim().isEmpty) &&
    value.npcPrice == 0 &&
    (value.sourceNote == null || value.sourceNote!.trim().isEmpty) &&
    (value.searchKeywords == null || value.searchKeywords!.trim().isEmpty) &&
    (value.vendor == null || value.vendor!.trim().isEmpty) &&
    (value.location == null || value.location!.trim().isEmpty) &&
    (value.marketId == null || value.marketId!.trim().isEmpty) &&
    (value.qualityBase == null || value.qualityBase!.trim().isEmpty) &&
    (value.qualityTier == null || value.qualityTier!.trim().isEmpty) &&
    value.extensions.isEmpty;
