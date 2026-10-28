import '../../data/catalog/catalog_repository.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/planner/ingredient_quality.dart';
import '../../domain/planner/planner_engine.dart';
import '../../domain/planner/planner_models.dart' as planner;
import '../../domain/planner/reviewed_acquisition_choices.dart';
import '../../domain/state/craft_completion.dart';
import '../../domain/state/planner_state.dart' as stored;

/// Assembles the immutable, mode-local planning snapshot consumed by feature
/// controllers. UI widgets never need to know how bundled and user-authored
/// recipe data are merged.
final class PlannerAssembly {
  const PlannerAssembly({this.engine = const PlannerEngine()});

  final PlannerEngine engine;

  planner.PlanResult build({
    required CatalogSnapshot catalog,
    required CraftMode mode,
    required stored.ModeState state,
    String? targetOverride,
    int? wantOverride,
  }) {
    final recipes = assembleRecipes(
      catalog: catalog.forMode(mode),
      state: state,
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: mode,
      processingRecipes: catalog.processing.items,
    );
    return engine.buildPlan(
      mode: mode,
      recipes: recipes,
      state: plannerState(state, target: targetOverride, want: wantOverride),
      rules: plannerRules(
        catalog.supportingData,
        npcPurchasePrices: CatalogRepository.cached(catalog).npcPurchasePrices,
      ),
      targetOverride: targetOverride,
      wantOverride: wantOverride,
    );
  }

  Map<String, Recipe> assembleRecipes({
    required ModeCatalog catalog,
    required stored.ModeState state,
    required Map<String, Object?> supportingData,
    Map<String, Object?>? sharedMetadata,
    required CraftMode mode,
    Map<String, Recipe> processingRecipes = const {},
  }) {
    final items = Map<String, Recipe>.of(catalog.items);
    final tombstones = <String>{
      for (final entry in state.recipeEdits.entries)
        if (entry.value == null && entry.key.trim().isNotEmpty)
          _fold(entry.key.trim()),
    };

    for (final entry in state.recipeEdits.entries) {
      final name = entry.key.trim();
      if (name.isEmpty) continue;
      final bundledKey = _foldedKey(catalog.items, name);
      final bundledRole = bundledKey == null
          ? RecipeRole.production
          : catalog.items[bundledKey]!.role;
      _removeFolded(items, name);
      final edited = entry.value;
      if (edited == null) continue;
      final effectiveRole = bundledRole != RecipeRole.production
          ? bundledRole
          : edited.role ?? bundledRole;
      final recipe = _recipeFromState(name, edited, role: effectiveRole);
      if (_recipeTypeAllowed(mode, recipe.type)) items[name] = recipe;
    }

    // Reviewed leaf materials stay bought unless the user explicitly chooses
    // their real Processing formula. Never turn a raw input into a substitute.
    for (final name in selectedProcessingAcquisitions(state)) {
      if (!hasReviewedProcessingChoice(mode, name)) continue;
      final localKey = _foldedKey(items, name);
      final processingKey = _foldedKey(processingRecipes, name);
      if (localKey == null ||
          processingKey == null ||
          !items[localKey]!.isManualConversion) {
        continue;
      }
      final processing = processingRecipes[processingKey]!;
      if (processing.isCraftable) items[localKey] = processing;
    }

    for (final entry in state.ingredientMeta.entries) {
      final name = entry.key.trim();
      if (name.isEmpty || tombstones.contains(_fold(name))) continue;
      final existingKey = _foldedKey(items, name);
      final existing = existingKey == null
          ? _gathered(name)
          : items.remove(existingKey)!;
      items[existingKey ?? name] = _withMetadata(existing, entry.value);
    }

    // Avalonia hydrates blood alternatives from the catalog's shared `meta`
    // block before planning. The Flutter parser deliberately keeps metadata on
    // ModeCatalog rather than flattening it into supportingData, so apply that
    // same normalization here while the immutable recipe snapshot is built.
    final metadata = sharedMetadata ?? catalog.metadata;
    _applyBloodGroupSubstitutes(items, metadata['bloodGroups']);
    _applySubstituteWorthRules(items, metadata['substituteWorthGroups']);

    final referencedNames = <String>{};
    for (final recipe in items.values) {
      final formulas = <Iterable<Ingredient>>[
        recipe.ingredients,
        for (final variant in recipe.variants) variant.ingredients,
      ];
      for (final ingredient in formulas.expand((value) => value)) {
        if (ingredient.name.trim().isNotEmpty) {
          referencedNames.add(ingredient.name.trim());
        }
        referencedNames.addAll(
          ingredient.options
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty),
        );
      }
    }
    for (final name in referencedNames) {
      if (_foldedKey(items, name) == null) items[name] = _gathered(name);
    }

    _ensureQualityAlternatives(items, supportingData);
    final hidden = state.hiddenItems.map(_fold).toSet();
    items.removeWhere((name, _) => hidden.contains(_fold(name)));
    return Map.unmodifiable(items);
  }

  planner.PlannerState plannerState(
    stored.ModeState state, {
    String? target,
    int? want,
  }) => planner.PlannerState(
    target: state.target,
    want: state.want,
    inventory: state.inventory,
    craftedInventory: craftCredits(state, target: target, want: want),
    completedSteps: state.completedSteps,
    ignoreTargetInventory: state.ignoreTargetInventory,
    ignoreIngredientInventory: state.ignoreIngredientInventory,
    alchemyMastery: state.alchemyMastery,
    cookingMastery: state.cookingMastery,
    processingMastery: state.processingMastery,
    useMassProcessing: state.useMassProcessing,
    substituteChoices: state.substituteChoices,
    ingredientGrades: state.ingredientGrades,
    recipeVariantChoices: state.recipeVariantChoices,
    marketPrices: state.market.prices,
    marketStock: state.market.stock,
    marketPreorderPrices: state.market.preorderPrices,
  );

  planner.PlannerRules plannerRules(
    Map<String, Object?> supportingData, {
    Map<String, double> npcPurchasePrices = const {},
  }) {
    final conversions = <String, planner.QualityConversionRule>{};
    for (final entry in _map(supportingData['qualityConversions']).entries) {
      final value = _map(entry.value);
      conversions[entry.key] = planner.QualityConversionRule(
        high: _qualityTier(value['high']),
        special: _qualityTier(value['special']),
      );
    }
    final cookingSpecial = <String, planner.SpecialQualityRule>{};
    for (final entry in _map(supportingData['cookingSpecialMap']).entries) {
      final value = _map(entry.value);
      final name = _string(value['name']);
      if (name == null || name.isEmpty) continue;
      cookingSpecial[entry.key] = planner.SpecialQualityRule(
        name: name,
        ratio: _positive(value['ratio'], fallback: 2),
      );
    }
    final vendorInfo = <String, planner.VendorSourceRule>{};
    for (final entry in _map(supportingData['vendorInfo']).entries) {
      final value = _map(entry.value);
      final price = _number(value['price']) ?? 0;
      vendorInfo[entry.key] = planner.VendorSourceRule(
        vendor: _trimmed(_string(value['vendor'])),
        role: _trimmed(_string(value['role'])),
        location: _trimmed(_string(value['location'])),
        price: price > 0 ? price : 0,
      );
    }
    final acquisitionInfo = <String, planner.ItemAcquisitionRule>{};
    for (final entry in _map(supportingData['acquisitionInfo']).entries) {
      final value = _map(entry.value);
      final routes = <planner.ItemAcquisitionRoute>[];
      final rawRoutes = value['routes'];
      if (rawRoutes is Iterable) {
        for (final rawRoute in rawRoutes) {
          final route = _map(rawRoute);
          final summary = _trimmed(_string(route['summary']));
          if (summary == null) continue;
          routes.add(
            planner.ItemAcquisitionRoute(
              kind: _trimmed(_string(route['kind'])) ?? 'other',
              summary: summary,
              availability:
                  _trimmed(_string(route['availability'])) ?? 'permanent',
              confidence: _trimmed(_string(route['confidence'])) ?? 'medium',
            ),
          );
        }
      }
      if (routes.isEmpty) continue;
      final rawItemId = _number(value['itemId']);
      acquisitionInfo[entry.key] = planner.ItemAcquisitionRule(
        canonicalName:
            _trimmed(_string(value['canonicalName'])) ?? entry.key.trim(),
        itemId: rawItemId?.toInt(),
        status: _trimmed(_string(value['status'])) ?? 'draft',
        reviewedAt: _trimmed(_string(value['reviewedAt'])) ?? '',
        routes: routes,
      );
    }
    return planner.PlannerRules(
      legacyUnavailableItems: _stringSet(
        supportingData['legacyUnavailableItems'],
      ),
      qualityIngredients: _stringSet(supportingData['qualityIngredients']),
      qualityConversions: conversions,
      blueElixirMap: _stringMap(supportingData['blueElixirMap']),
      cookingSpecialMap: cookingSpecial,
      marketIds: _stringMap(supportingData['marketIds']),
      marketNameAliases: _stringMap(supportingData['marketNameAliases']),
      fallbackMarketPrices: _doubleMap(supportingData['fallbackMarketPrices']),
      itemWeightIds: _stringMap(supportingData['itemWeightIds']),
      itemWeightsLtById: _doubleMap(supportingData['itemWeightsLtById']),
      vendorInfo: vendorInfo,
      npcPurchasePrices: npcPurchasePrices,
      acquisitionInfo: acquisitionInfo,
    );
  }
}

Recipe _recipeFromState(
  String name,
  stored.RecipeState source, {
  required RecipeRole role,
}) {
  const allowed = {
    'alchemy',
    'simple_alchemy',
    'cooking',
    'processing',
    'gathered',
  };
  final type = allowed.contains(source.type.toLowerCase())
      ? source.type.toLowerCase()
      : 'gathered';
  final ingredients = type == 'gathered'
      ? const <Ingredient>[]
      : source.ingredients
            .where(
              (ingredient) =>
                  ingredient.name.trim().isNotEmpty && ingredient.quantity > 0,
            )
            .map(
              (ingredient) => Ingredient(
                name: ingredient.name.trim(),
                quantity: ingredient.quantity,
                options: ingredient.options,
                substituteGroup: _trimmed(ingredient.substituteGroup),
                substituteRatios: ingredient.substituteRatios,
              ),
            )
            .toList(growable: false);
  return Recipe(
    name: name,
    type: type,
    baseOutput: source.baseOutput > 0 ? source.baseOutput : 1,
    group: _trimmed(source.group),
    method: _trimmed(source.method),
    ingredients: ingredients,
    marketId: _trimmed(source.marketId),
    sourceNote: _trimmed(source.sourceNote),
    vendor: _trimmed(source.vendor),
    location: _trimmed(source.location),
    npcPrice: source.npcPrice < 0 ? 0 : source.npcPrice,
    qualityBase: _trimmed(source.qualityBase),
    qualityGrade: _trimmed(source.qualityGrade),
    outputMinimum: source.outputMinimum,
    outputMaximum: source.outputMaximum,
    role: role,
  );
}

Recipe _withMetadata(Recipe recipe, stored.IngredientMetadata metadata) =>
    Recipe(
      name: recipe.name,
      type: recipe.type,
      baseOutput: recipe.baseOutput,
      group: _trimmed(metadata.category) ?? recipe.group,
      method: recipe.method,
      ingredients: recipe.ingredients,
      marketId: _trimmed(metadata.marketId) ?? recipe.marketId,
      sourceNote: _trimmed(metadata.sourceNote) ?? recipe.sourceNote,
      vendor: _trimmed(metadata.vendor) ?? recipe.vendor,
      location: _trimmed(metadata.location) ?? recipe.location,
      npcPrice: metadata.npcPrice > 0 ? metadata.npcPrice : recipe.npcPrice,
      qualityBase: _trimmed(metadata.qualityBase) ?? recipe.qualityBase,
      qualityGrade:
          _normalizedQuality(metadata.qualityTier) ?? recipe.qualityGrade,
      outputMinimum: recipe.outputMinimum,
      outputMaximum: recipe.outputMaximum,
      role: recipe.role,
      variants: recipe.variants,
      defaultVariantId: recipe.defaultVariantId,
    );

void _applyBloodGroupSubstitutes(
  Map<String, Recipe> recipes,
  Object? groupsValue,
) {
  final groups = _map(groupsValue);
  if (groups.isEmpty) return;

  final groupOptions = <String, List<String>>{};
  final bloodToGroup = <String, String>{};
  for (final entry in groups.entries) {
    final rawOptions = entry.value;
    if (rawOptions is! Iterable) continue;
    final seen = <String>{};
    final options = <String>[];
    for (final raw in rawOptions) {
      final option = _string(raw)?.trim() ?? '';
      if (option.isEmpty || !seen.add(_fold(option))) continue;
      options.add(option);
    }
    if (options.length <= 1) continue;
    final groupName = 'Blood ${entry.key}';
    groupOptions[groupName] = List<String>.unmodifiable(options);
    for (final option in options) {
      bloodToGroup[_fold(option)] = groupName;
    }
  }
  if (groupOptions.isEmpty) return;

  (List<Ingredient>, bool) hydrate(Iterable<Ingredient> source) {
    var changed = false;
    final ingredients = <Ingredient>[];
    for (final ingredient in source) {
      final groupName = bloodToGroup[_fold(ingredient.name)];
      if (groupName == null) {
        ingredients.add(ingredient);
        continue;
      }

      final seen = <String>{};
      final options = <String>[
        for (final option in <String>[
          ...groupOptions[groupName]!,
          ...ingredient.options,
        ])
          if (seen.add(_fold(option))) option,
      ];
      final substituteGroup = _trimmed(ingredient.substituteGroup) ?? groupName;
      final sameOptions =
          options.length == ingredient.options.length &&
          List.generate(
            options.length,
            (index) => index,
          ).every((index) => options[index] == ingredient.options[index]);
      if (sameOptions && substituteGroup == ingredient.substituteGroup) {
        ingredients.add(ingredient);
        continue;
      }

      changed = true;
      ingredients.add(
        Ingredient(
          name: ingredient.name,
          quantity: ingredient.quantity,
          options: options,
          substituteGroup: substituteGroup,
          substituteRatios: ingredient.substituteRatios,
        ),
      );
    }
    return (ingredients, changed);
  }

  for (final entry in recipes.entries.toList(growable: false)) {
    final recipe = entry.value;
    final (ingredients, ingredientsChanged) = hydrate(recipe.ingredients);
    var variantsChanged = false;
    final variants = <RecipeVariant>[
      for (final variant in recipe.variants)
        () {
          final (variantIngredients, changed) = hydrate(variant.ingredients);
          variantsChanged = variantsChanged || changed;
          return RecipeVariant(
            id: variant.id,
            label: variant.label,
            type: variant.type,
            baseOutput: variant.baseOutput,
            method: variant.method,
            ingredients: variantIngredients,
            outputMinimum: variant.outputMinimum,
            outputMaximum: variant.outputMaximum,
            routeId: variant.routeId,
            batchMultiplier: variant.batchMultiplier,
          );
        }(),
    ];
    if (!ingredientsChanged && !variantsChanged) continue;
    recipes[entry.key] = Recipe(
      name: recipe.name,
      type: recipe.type,
      baseOutput: recipe.baseOutput,
      group: recipe.group,
      method: recipe.method,
      ingredients: ingredients,
      marketId: recipe.marketId,
      sourceNote: recipe.sourceNote,
      vendor: recipe.vendor,
      location: recipe.location,
      npcPrice: recipe.npcPrice,
      qualityBase: recipe.qualityBase,
      qualityGrade: recipe.qualityGrade,
      outputMinimum: recipe.outputMinimum,
      outputMaximum: recipe.outputMaximum,
      role: recipe.role,
      variants: variants,
      defaultVariantId: recipe.defaultVariantId,
    );
  }
}

/// Applies the game's Worth rules as exact per-craft replacement quantities.
///
/// A Worth value says how many units of the group's basic ingredient one unit
/// replaces. The original ingredient can itself have Worth greater than one,
/// so the relative amount is:
///
/// `ceil(recipe quantity * original Worth / selected Worth)`
///
/// The ceiling belongs here, before the planner multiplies by craft count. If
/// it were applied after multiplication, ten crafts needing seven Wolf Blood
/// could incorrectly use 35 Flamingo Blood instead of four per craft (40).
void _applySubstituteWorthRules(
  Map<String, Recipe> recipes,
  Object? groupsValue,
) {
  final groups = _map(groupsValue);
  if (groups.isEmpty) return;

  final worthByItem = <String, Map<String, double>>{};
  final optionsByItem = <String, List<String>>{};
  final groupByItem = <String, String>{};
  for (final groupEntry in groups.entries) {
    final worths = <String, double>{};
    final options = <String>[];
    for (final entry in _map(groupEntry.value).entries) {
      final worth = _number(entry.value);
      if (worth == null || worth <= 0 || entry.key.trim().isEmpty) continue;
      final name = entry.key.trim();
      worths[_fold(name)] = worth;
      options.add(name);
    }
    if (worths.length <= 1) continue;
    final family = Map<String, double>.unmodifiable(worths);
    final familyOptions = List<String>.unmodifiable(options);
    final groupName = groupEntry.key.trim();
    for (final foldedName in family.keys) {
      worthByItem[foldedName] = family;
      optionsByItem[foldedName] = familyOptions;
      if (groupName.isNotEmpty) groupByItem[foldedName] = groupName;
    }
  }
  if (worthByItem.isEmpty) return;

  (List<Ingredient>, bool) apply(Iterable<Ingredient> source) {
    var changed = false;
    final ingredients = <Ingredient>[];
    for (final ingredient in source) {
      final foldedIngredient = _fold(ingredient.name);
      final family = worthByItem[foldedIngredient];
      final originalWorth = family?[foldedIngredient];
      if (family == null || originalWorth == null || ingredient.quantity <= 0) {
        ingredients.add(ingredient);
        continue;
      }

      final seenOptions = <String>{};
      final options = <String>[
        for (final option in <String>[
          ingredient.name,
          ...?optionsByItem[foldedIngredient],
          ...ingredient.options,
        ])
          if (seenOptions.add(_fold(option))) option,
      ];
      final substituteGroup =
          _trimmed(ingredient.substituteGroup) ?? groupByItem[foldedIngredient];
      final ratios = Map<String, double>.of(ingredient.substituteRatios);
      var ingredientChanged =
          substituteGroup != ingredient.substituteGroup ||
          options.length != ingredient.options.length ||
          List.generate(options.length, (index) => index).any(
            (index) =>
                index >= ingredient.options.length ||
                options[index] != ingredient.options[index],
          );
      final seen = <String>{};
      for (final option in options) {
        if (!seen.add(_fold(option))) continue;
        final selectedWorth = family[_fold(option)];
        if (selectedWorth == null) continue;

        double? explicitRatio;
        for (final entry in ratios.entries) {
          if (_fold(entry.key) == _fold(option) && entry.value > 0) {
            explicitRatio = entry.value;
            break;
          }
        }
        if (explicitRatio != null) continue;

        final requiredPerCraft =
            (ingredient.quantity * originalWorth / selectedWorth)
                .ceilToDouble();
        ratios[option] = requiredPerCraft / ingredient.quantity;
        ingredientChanged = true;
      }
      if (!ingredientChanged) {
        ingredients.add(ingredient);
        continue;
      }

      changed = true;
      ingredients.add(
        Ingredient(
          name: ingredient.name,
          quantity: ingredient.quantity,
          options: options,
          substituteGroup: substituteGroup,
          substituteRatios: ratios,
        ),
      );
    }
    return (ingredients, changed);
  }

  for (final entry in recipes.entries.toList(growable: false)) {
    final recipe = entry.value;
    if (recipeHasAuthoritativeQualityVariants(recipe.name)) {
      // Tenacious Origin has three authoritative, complete recipes: all-normal,
      // all-high-quality, or all-special herbs. Applying each herb family's
      // generic Worth substitutions here would invent mixed-quality formulas
      // that the game does not declare.
      continue;
    }
    final (ingredients, ingredientsChanged) = apply(recipe.ingredients);
    var variantsChanged = false;
    final variants = <RecipeVariant>[
      for (final variant in recipe.variants)
        () {
          final (variantIngredients, changed) = apply(variant.ingredients);
          variantsChanged = variantsChanged || changed;
          return RecipeVariant(
            id: variant.id,
            label: variant.label,
            type: variant.type,
            baseOutput: variant.baseOutput,
            method: variant.method,
            ingredients: variantIngredients,
            outputMinimum: variant.outputMinimum,
            outputMaximum: variant.outputMaximum,
            routeId: variant.routeId,
            batchMultiplier: variant.batchMultiplier,
          );
        }(),
    ];
    if (!ingredientsChanged && !variantsChanged) continue;
    recipes[entry.key] = Recipe(
      name: recipe.name,
      type: recipe.type,
      baseOutput: recipe.baseOutput,
      group: recipe.group,
      method: recipe.method,
      ingredients: ingredients,
      marketId: recipe.marketId,
      sourceNote: recipe.sourceNote,
      vendor: recipe.vendor,
      location: recipe.location,
      npcPrice: recipe.npcPrice,
      qualityBase: recipe.qualityBase,
      qualityGrade: recipe.qualityGrade,
      outputMinimum: recipe.outputMinimum,
      outputMaximum: recipe.outputMaximum,
      role: recipe.role,
      variants: variants,
      defaultVariantId: recipe.defaultVariantId,
    );
  }
}

void _ensureQualityAlternatives(
  Map<String, Recipe> items,
  Map<String, Object?> supporting,
) {
  final qualityIngredients = _stringSet(supporting['qualityIngredients']);
  final conversions = _map(supporting['qualityConversions']);
  final blueElixirMap = _stringMap(supporting['blueElixirMap']);
  final cookingSpecialMap = _map(supporting['cookingSpecialMap']);
  final qualityIngredientKeys = qualityIngredients.map(_fold).toSet();
  final qualityBases = <String>[];

  void addQualityBase(String name) {
    if (name.trim().isEmpty ||
        qualityBases.any((candidate) => _fold(candidate) == _fold(name))) {
      return;
    }
    qualityBases.add(name);
  }

  for (final name in qualityIngredients) {
    addQualityBase(name);
  }
  for (final name in items.keys) {
    if (_qualityKindForAlternatives(
          name,
          qualityIngredientKeys: qualityIngredientKeys,
          blueElixirMap: blueElixirMap,
          cookingSpecialMap: cookingSpecialMap,
        ) ==
        'material') {
      addQualityBase(name);
    }
  }

  void add(String name, String baseName, String? group, String grade) {
    if (name.trim().isEmpty || _foldedKey(items, name) != null) return;
    items[name] = Recipe(
      name: name,
      type: 'gathered',
      baseOutput: 1,
      group: group ?? 'Base Items',
      method: null,
      ingredients: const [],
      marketId: null,
      sourceNote: null,
      vendor: null,
      location: null,
      npcPrice: 0,
      qualityBase: baseName,
      qualityGrade: grade,
      outputMinimum: null,
      outputMaximum: null,
    );
  }

  for (final baseName in qualityBases) {
    final key = _foldedKey(items, baseName);
    if (key == null) continue;
    final base = items[key]!;
    final conversion = _map(_foldedValue(conversions, baseName));
    final high = _map(conversion['high']);
    final special = _map(conversion['special']);
    add(
      _string(high['name']) ?? 'High-Quality $baseName',
      baseName,
      base.group,
      'high',
    );
    add(
      _string(special['name']) ?? 'Special $baseName',
      baseName,
      base.group,
      'special',
    );
  }
  for (final entry in blueElixirMap.entries) {
    final key = _foldedKey(items, entry.key);
    if (key != null) add(entry.value, entry.key, items[key]!.group, 'blue');
  }
  for (final entry in cookingSpecialMap.entries) {
    final key = _foldedKey(items, entry.key);
    final name = _string(_map(entry.value)['name']);
    if (key != null && name != null) {
      add(name, entry.key, items[key]!.group ?? 'Cooking', 'blue');
    }
  }
}

String _qualityKindForAlternatives(
  String name, {
  required Set<String> qualityIngredientKeys,
  required Map<String, String> blueElixirMap,
  required Map<String, Object?> cookingSpecialMap,
}) {
  if (_foldedKey(blueElixirMap, name) != null) return 'elixir';
  if (_fold(name) == 'oatmeal') return 'oatmeal';
  if (_foldedKey(cookingSpecialMap, name) != null) return 'cooked';
  if (qualityIngredientKeys.contains(_fold(name))) return 'material';
  final folded = _fold(name);
  if (folded.contains('mushroom') &&
      !folded.contains('truffle') &&
      !folded.contains('high-quality') &&
      !folded.contains('special') &&
      !folded.contains('big ') &&
      !folded.contains('hypha')) {
    return 'material';
  }
  return '';
}

Recipe _gathered(String name) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: const [],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);

bool _recipeTypeAllowed(CraftMode mode, String type) => switch (mode) {
  CraftMode.cooking => {'cooking', 'processing', 'gathered'}.contains(type),
  CraftMode.processing => {
    'processing',
    'simple_alchemy',
    'cooking',
    'gathered',
  }.contains(type),
  CraftMode.alchemy => {
    'alchemy',
    'simple_alchemy',
    'processing',
    'gathered',
  }.contains(type),
};

planner.QualityTierRule? _qualityTier(Object? value) {
  final map = _map(value);
  final name = _string(map['name']);
  if (name == null || name.isEmpty) return null;
  return planner.QualityTierRule(
    name: name,
    ratio: _positive(map['ratio'], fallback: 1),
  );
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry('$key', item));
}

Map<String, String> _stringMap(Object? value) =>
    _map(value).map((key, item) => MapEntry(key, _string(item) ?? ''));

Map<String, double> _doubleMap(Object? value) {
  final result = <String, double>{};
  for (final entry in _map(value).entries) {
    final parsed = _number(entry.value);
    if (parsed != null) result[entry.key] = parsed;
  }
  return result;
}

Set<String> _stringSet(Object? value) => value is Iterable
    ? value.map(_string).whereType<String>().toSet()
    : const {};

Object? _foldedValue(Map<String, Object?> map, String name) {
  for (final entry in map.entries) {
    if (_fold(entry.key) == _fold(name)) return entry.value;
  }
  return null;
}

String? _foldedKey<T>(Map<String, T> map, String name) {
  if (map.containsKey(name)) return name;
  for (final key in map.keys) {
    if (_fold(key) == _fold(name)) return key;
  }
  return null;
}

void _removeFolded<T>(Map<String, T> map, String name) {
  final keys = map.keys.where((key) => _fold(key) == _fold(name)).toList();
  for (final key in keys) {
    map.remove(key);
  }
}

String _fold(String value) => value.trim().toLowerCase();

String? _trimmed(String? value) {
  final result = value?.trim();
  return result == null || result.isEmpty ? null : result;
}

String? _normalizedQuality(String? value) {
  final normalized = _trimmed(value);
  return normalized == null || normalized.toLowerCase() == 'none'
      ? null
      : normalized;
}

String? _string(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return null;
}

double? _number(Object? value) {
  final result = value is num ? value.toDouble() : double.tryParse('$value');
  return result != null && result.isFinite ? result : null;
}

double _positive(Object? value, {required double fallback}) {
  final result = _number(value);
  return result != null && result > 0 ? result : fallback;
}
