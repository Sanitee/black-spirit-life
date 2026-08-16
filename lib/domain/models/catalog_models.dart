import 'dart:collection';

import 'craft_mode.dart';

/// Distinguishes automatic production recipes from reference-only conversions.
///
/// Manual conversions and salvage records retain their ingredients and output
/// metadata for auditing, but are never offered as planner targets or expanded
/// automatically by the planner. Deliberately curated references may still be
/// browsed in the Recipe Book for their factual material lists.
enum RecipeRole {
  production,
  manualConversion,
  salvage;

  String get catalogValue => switch (this) {
    RecipeRole.production => 'production',
    RecipeRole.manualConversion => 'manual_conversion',
    RecipeRole.salvage => 'salvage',
  };

  static RecipeRole fromCatalogValue(String? value) {
    final normalized = value?.trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );
    return switch (normalized) {
      null || '' || 'production' => RecipeRole.production,
      'manual_conversion' || 'manualconversion' => RecipeRole.manualConversion,
      'salvage' => RecipeRole.salvage,
      _ => throw FormatException('Unknown recipe role "$value".'),
    };
  }
}

class Ingredient {
  Ingredient({
    required this.name,
    required this.quantity,
    required Iterable<String> options,
    required this.substituteGroup,
    required Map<String, double> substituteRatios,
  }) : options = List.unmodifiable(options),
       substituteRatios = UnmodifiableMapView(substituteRatios);

  final String name;
  final double quantity;
  final List<String> options;
  final String? substituteGroup;
  final Map<String, double> substituteRatios;
}

/// One complete, correlated way to produce a recipe's output.
///
/// A variant is deliberately different from an [Ingredient.options] list:
/// options are interchangeable inside one ingredient row, whereas a variant
/// replaces the whole formula as a unit.
class RecipeVariant {
  RecipeVariant({
    required this.id,
    required this.label,
    required this.type,
    required this.baseOutput,
    required this.method,
    required Iterable<Ingredient> ingredients,
    required this.outputMinimum,
    required this.outputMaximum,
    String? routeId,
    this.batchMultiplier = 1,
  }) : routeId = _recipeVariantRouteId(routeId, id),
       ingredients = List.unmodifiable(ingredients) {
    if (batchMultiplier < 1) {
      throw ArgumentError.value(
        batchMultiplier,
        'batchMultiplier',
        'Recipe batch multipliers must be positive.',
      );
    }
  }

  final String id;
  final String label;
  final String routeId;
  final int batchMultiplier;
  final String type;
  final double baseOutput;
  final String? method;
  final List<Ingredient> ingredients;
  final double? outputMinimum;
  final double? outputMaximum;
}

class RecipeVariantRoute {
  RecipeVariantRoute({
    required this.id,
    required this.label,
    required Iterable<RecipeVariant> variants,
  }) : variants = List.unmodifiable(variants);

  final String id;
  final String label;
  final List<RecipeVariant> variants;

  RecipeVariant? variantForBatch(int batchMultiplier) {
    for (final variant in variants) {
      if (variant.batchMultiplier == batchMultiplier) return variant;
    }
    return null;
  }

  RecipeVariant get fallbackVariant {
    final singleBatch = variantForBatch(1);
    if (singleBatch != null) return singleBatch;
    return variants.reduce(
      (current, candidate) =>
          candidate.batchMultiplier < current.batchMultiplier
          ? candidate
          : current,
    );
  }
}

class Recipe {
  Recipe({
    required this.name,
    required this.type,
    required this.baseOutput,
    required this.group,
    required this.method,
    required Iterable<Ingredient> ingredients,
    required this.marketId,
    required this.sourceNote,
    required this.vendor,
    required this.location,
    required this.npcPrice,
    required this.qualityBase,
    required this.qualityGrade,
    required this.outputMinimum,
    required this.outputMaximum,
    this.role = RecipeRole.production,
    Iterable<RecipeVariant> variants = const <RecipeVariant>[],
    this.defaultVariantId,
  }) : ingredients = List.unmodifiable(ingredients),
       variants = List.unmodifiable(variants);

  final String name;
  final String type;
  final double baseOutput;
  final String? group;
  final String? method;
  final List<Ingredient> ingredients;
  final String? marketId;
  final String? sourceNote;
  final String? vendor;
  final String? location;
  final double npcPrice;
  final String? qualityBase;
  final String? qualityGrade;
  final double? outputMinimum;
  final double? outputMaximum;
  final RecipeRole role;
  final List<RecipeVariant> variants;
  final String? defaultVariantId;

  bool get hasRecordedRecipe => ingredients.isNotEmpty;

  bool get isCraftable =>
      role == RecipeRole.production &&
      hasRecordedRecipe &&
      name.trim().toLowerCase() != 'assorted side dishes';

  bool get isReferenceOnly => role != RecipeRole.production;

  bool get isManualConversion => role == RecipeRole.manualConversion;

  bool get isSalvageOnly => role == RecipeRole.salvage;

  bool get hasRecipeVariants => variants.length > 1;

  List<RecipeVariantRoute> get variantRoutes {
    final routes = <RecipeVariantRoute>[];
    for (final variant in variants) {
      final routeIndex = routes.indexWhere(
        (route) => _sameCatalogValue(route.id, variant.routeId),
      );
      if (routeIndex < 0) {
        routes.add(
          RecipeVariantRoute(
            id: variant.routeId,
            label: variant.label,
            variants: <RecipeVariant>[variant],
          ),
        );
        continue;
      }
      final route = routes[routeIndex];
      routes[routeIndex] = RecipeVariantRoute(
        id: route.id,
        label: route.label,
        variants: <RecipeVariant>[...route.variants, variant],
      );
    }
    return List<RecipeVariantRoute>.unmodifiable(routes);
  }

  List<int> get variantBatchMultipliers {
    final multipliers =
        variants.map((variant) => variant.batchMultiplier).toSet().toList()
          ..sort();
    return List<int>.unmodifiable(multipliers);
  }

  bool get hasRecipeRouteChoices => variantRoutes.length > 1;

  bool get hasRecipeBatchChoices => variantBatchMultipliers.length > 1;

  RecipeVariant? variantById(String? id) {
    final normalized = id?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final variant in variants) {
      if (_sameCatalogValue(variant.id, normalized)) return variant;
    }
    return null;
  }

  RecipeVariant? get defaultVariant {
    if (variants.isEmpty) return null;
    return variantById(defaultVariantId) ?? variants.first;
  }

  String? resolvedVariantId(String? savedId) =>
      (variantById(savedId) ?? defaultVariant)?.id;

  RecipeVariantRoute? variantRouteById(String? routeId) {
    final normalized = routeId?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final route in variantRoutes) {
      if (_sameCatalogValue(route.id, normalized)) return route;
    }
    return null;
  }

  RecipeVariant? variantForRouteAndBatch(String routeId, int batchMultiplier) =>
      variantRouteById(routeId)?.variantForBatch(batchMultiplier);

  RecipeVariant? resolveRouteSelection(String? savedId, String routeId) {
    final route = variantRouteById(routeId);
    if (route == null) return null;
    final current = variantById(savedId) ?? defaultVariant;
    return route.variantForBatch(current?.batchMultiplier ?? 1) ??
        route.fallbackVariant;
  }

  RecipeVariant? resolveBatchSelection(String? savedId, int batchMultiplier) {
    final current = variantById(savedId) ?? defaultVariant;
    if (current == null) return null;
    return variantForRouteAndBatch(current.routeId, batchMultiplier);
  }

  /// Returns this recipe with the selected complete formula made active.
  ///
  /// The variant definitions remain attached so presentation layers can render
  /// the selector without having to keep a second catalog object in sync.
  Recipe resolveVariant(String? savedId) {
    final selected = variantById(savedId) ?? defaultVariant;
    if (selected == null) return this;
    return Recipe(
      name: name,
      type: selected.type,
      baseOutput: selected.baseOutput,
      group: group,
      method: selected.method,
      ingredients: selected.ingredients,
      marketId: marketId,
      sourceNote: sourceNote,
      vendor: vendor,
      location: location,
      npcPrice: npcPrice,
      qualityBase: qualityBase,
      qualityGrade: qualityGrade,
      outputMinimum: selected.outputMinimum,
      outputMaximum: selected.outputMaximum,
      role: role,
      variants: variants,
      defaultVariantId: defaultVariantId,
    );
  }
}

bool _sameCatalogValue(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();

String _recipeVariantRouteId(String? routeId, String variantId) {
  final normalized = routeId?.trim();
  return normalized == null || normalized.isEmpty ? variantId : normalized;
}

class ModeCatalog {
  ModeCatalog({
    required this.mode,
    required Map<String, Recipe> items,
    required Map<String, String> iconDataUris,
    required Map<String, Object?> defaults,
    required Map<String, Object?> metadata,
    required Map<String, String> searchAliases,
  }) : items = UnmodifiableMapView(items),
       iconDataUris = UnmodifiableMapView(iconDataUris),
       defaults = UnmodifiableMapView(defaults),
       metadata = UnmodifiableMapView(metadata),
       searchAliases = UnmodifiableMapView(searchAliases);

  final CraftMode mode;
  final Map<String, Recipe> items;
  final Map<String, String> iconDataUris;
  final Map<String, Object?> defaults;
  final Map<String, Object?> metadata;
  final Map<String, String> searchAliases;

  int get auditedCraftableCount =>
      items.values.where((item) => item.ingredients.isNotEmpty).length;
  int get plannerCraftableCount =>
      items.values.where((item) => item.isCraftable).length;
  int get ingredientRowCount =>
      items.values.fold(0, (sum, recipe) => sum + recipe.ingredients.length);
}

class CaseCollision {
  CaseCollision({
    required this.jsonPath,
    required Iterable<String> spellings,
    required this.valuesEqual,
  }) : spellings = List.unmodifiable(spellings);

  final String jsonPath;
  final List<String> spellings;
  final bool valuesEqual;
}

class CatalogSnapshot {
  CatalogSnapshot({
    required this.sourceSha256,
    required this.sourceByteCount,
    required this.alchemy,
    required this.cooking,
    required this.processing,
    required Map<String, Object?> supportingData,
    required Iterable<CaseCollision> collisions,
  }) : supportingData = UnmodifiableMapView(supportingData),
       collisions = List.unmodifiable(collisions);

  final String sourceSha256;
  final int sourceByteCount;
  final ModeCatalog alchemy;
  final ModeCatalog cooking;
  final ModeCatalog processing;
  final Map<String, Object?> supportingData;
  final List<CaseCollision> collisions;

  ModeCatalog forMode(CraftMode mode) => switch (mode) {
    CraftMode.alchemy => alchemy,
    CraftMode.cooking => cooking,
    CraftMode.processing => processing,
  };

  int get totalItemCount =>
      alchemy.items.length + cooking.items.length + processing.items.length;
  int get totalCraftableCount =>
      alchemy.auditedCraftableCount +
      cooking.auditedCraftableCount +
      processing.auditedCraftableCount;
  int get totalIngredientRowCount =>
      alchemy.ingredientRowCount +
      cooking.ingredientRowCount +
      processing.ingredientRowCount;
}
