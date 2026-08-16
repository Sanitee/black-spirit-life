import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';

const productionCatalogSha256 =
    '9aa828a2340ffdd39f152b9c5b1b6df4c705df2a465ceb6124811056edb1a1cc';
const productionCatalogByteCount = 16025014;

class CatalogFormatException implements Exception {
  const CatalogFormatException(this.message);

  final String message;

  @override
  String toString() => 'CatalogFormatException: $message';
}

class BundledCatalogParser {
  const BundledCatalogParser();

  CatalogSnapshot parse(String source) {
    final bytes = utf8.encode(source);
    final sourceHash = sha256.convert(bytes).toString();
    if (bytes.length != productionCatalogByteCount ||
        sourceHash != productionCatalogSha256) {
      throw CatalogFormatException(
        'The bundled production catalog does not match the approved dataset.',
      );
    }

    final decoded = jsonDecode(source);
    final root = _objectMap(decoded, r'$');
    final alchemy = _modeCatalog(
      mode: CraftMode.alchemy,
      itemsValue: root['items'],
      iconsValue: root['itemIcons'],
      defaultsValue: root['defaults'],
      metadataValue: root['meta'],
      itemPath: r'$.items',
    );
    final cookingRoot = _objectMap(root['cooking'], r'$.cooking');
    final cooking = _modeCatalog(
      mode: CraftMode.cooking,
      itemsValue: cookingRoot['items'],
      iconsValue: cookingRoot['itemIcons'],
      defaultsValue: cookingRoot['defaults'],
      metadataValue: cookingRoot['meta'],
      itemPath: r'$.cooking.items',
    );
    final processingRoot = _objectMap(root['processing'], r'$.processing');
    final processing = _modeCatalog(
      mode: CraftMode.processing,
      itemsValue: processingRoot['items'],
      iconsValue: processingRoot['itemIcons'],
      defaultsValue: processingRoot['defaults'],
      metadataValue: processingRoot['meta'],
      aliasesValue: processingRoot['searchAliases'],
      itemPath: r'$.processing.items',
    );
    _verifyNoBundledPersonalDefaults(<ModeCatalog>[
      alchemy,
      cooking,
      processing,
    ]);

    final supporting = <String, Object?>{};
    for (final entry in root.entries) {
      if (!const {
        'items',
        'itemIcons',
        'defaults',
        'meta',
        'cooking',
        'processing',
      }.contains(entry.key)) {
        supporting[entry.key] = entry.value;
      }
    }
    final collisions = <CaseCollision>[];
    _findCaseCollisions(root, r'$', collisions);

    final snapshot = CatalogSnapshot(
      sourceSha256: sourceHash,
      sourceByteCount: bytes.length,
      alchemy: alchemy,
      cooking: cooking,
      processing: processing,
      supportingData: supporting,
      collisions: collisions,
    );
    _verifyProductionCounts(snapshot);
    return snapshot;
  }

  void _verifyNoBundledPersonalDefaults(Iterable<ModeCatalog> modes) {
    for (final mode in modes) {
      final inventory = mode.defaults['inv'];
      final favorites = mode.defaults['favoriteRecipes'];
      if (inventory is! Map ||
          inventory.isNotEmpty ||
          favorites is! List ||
          favorites.isNotEmpty) {
        throw CatalogFormatException(
          'Bundled ${mode.mode.label} defaults contain personal inventory '
          'or favorites.',
        );
      }
    }
  }

  ModeCatalog _modeCatalog({
    required CraftMode mode,
    required Object? itemsValue,
    required Object? iconsValue,
    required Object? defaultsValue,
    required Object? metadataValue,
    required String itemPath,
    Object? aliasesValue,
  }) {
    final rawItems = _objectMap(itemsValue, itemPath);
    final items = <String, Recipe>{};
    for (final entry in rawItems.entries) {
      items[entry.key] = _recipe(
        entry.key,
        entry.value,
        '$itemPath.${entry.key}',
      );
    }
    return ModeCatalog(
      mode: mode,
      items: items,
      iconDataUris: _stringMap(iconsValue),
      defaults: _objectMap(defaultsValue, r'$.defaults'),
      metadata: _objectMap(metadataValue, r'$.meta'),
      searchAliases: _searchAliasMap(aliasesValue),
    );
  }

  Recipe _recipe(String name, Object? value, String path) {
    final map = _objectMap(value, path);
    final type = _flexibleString(map['type']) ?? 'material';
    final baseOutput = _finiteDouble(map['baseOutput']) ?? 1;
    final method = _flexibleString(map['method']);
    final outputMinimum = _finiteDouble(map['outputMin']);
    final outputMaximum = _finiteDouble(map['outputMax']);
    final ingredients = <Ingredient>[];
    final rawIngredients = map['ingredients'];
    if (rawIngredients is List) {
      for (var index = 0; index < rawIngredients.length; index++) {
        ingredients.add(
          _ingredient(rawIngredients[index], '$path.ingredients[$index]'),
        );
      }
    }
    final variants = _recipeVariants(
      map['variants'],
      '$path.variants',
      fallbackType: type,
      fallbackBaseOutput: baseOutput,
      fallbackMethod: method,
      fallbackOutputMinimum: outputMinimum,
      fallbackOutputMaximum: outputMaximum,
    );
    final defaultVariantId = _flexibleString(map['defaultVariantId'])?.trim();
    if (variants.isNotEmpty) {
      if (variants.length < 2) {
        throw CatalogFormatException(
          '$path.variants must contain at least two complete formulas.',
        );
      }
      if (defaultVariantId == null || defaultVariantId.isEmpty) {
        throw CatalogFormatException(
          '$path.defaultVariantId is required when variants are present.',
        );
      }
      if (!variants.any(
        (variant) => variant.id.toLowerCase() == defaultVariantId.toLowerCase(),
      )) {
        throw CatalogFormatException(
          '$path.defaultVariantId does not identify a declared variant.',
        );
      }
    } else if (defaultVariantId != null && defaultVariantId.isNotEmpty) {
      throw CatalogFormatException(
        '$path.defaultVariantId requires a variants list.',
      );
    }
    return Recipe(
      name: name,
      type: type,
      baseOutput: baseOutput,
      group: _flexibleString(map['group']),
      method: method,
      ingredients: ingredients,
      marketId: _flexibleString(map['marketId']),
      sourceNote: _flexibleString(map['sourceNote']),
      vendor: _flexibleString(map['vendor']),
      location: _flexibleString(map['location']),
      npcPrice: _finiteDouble(map['npcPrice']) ?? 0,
      qualityBase: _flexibleString(map['qualityBase']),
      qualityGrade: _flexibleString(map['qualityGrade']),
      outputMinimum: outputMinimum,
      outputMaximum: outputMaximum,
      role: _recipeRole(map['recipeRole'], '$path.recipeRole'),
      variants: variants,
      defaultVariantId: defaultVariantId,
    );
  }

  List<RecipeVariant> _recipeVariants(
    Object? value,
    String path, {
    required String fallbackType,
    required double fallbackBaseOutput,
    required String? fallbackMethod,
    required double? fallbackOutputMinimum,
    required double? fallbackOutputMaximum,
  }) {
    if (value == null) return const <RecipeVariant>[];
    if (value is! List) {
      throw CatalogFormatException('$path must be a JSON array.');
    }
    final variants = <RecipeVariant>[];
    final ids = <String>{};
    final routeLabels = <String, String>{};
    final routeBatches = <String>{};
    for (var index = 0; index < value.length; index += 1) {
      final variantPath = '$path[$index]';
      final map = _objectMap(value[index], variantPath);
      final id = (_flexibleString(map['id']) ?? '').trim();
      final label = (_flexibleString(map['label']) ?? '').trim();
      if (id.isEmpty) {
        throw CatalogFormatException('$variantPath.id must not be empty.');
      }
      if (!ids.add(id.toLowerCase())) {
        throw CatalogFormatException('$path contains duplicate id "$id".');
      }
      if (label.isEmpty) {
        throw CatalogFormatException('$variantPath.label must not be empty.');
      }
      final parsedRouteId = _flexibleString(map['routeId'])?.trim();
      if (map.containsKey('routeId') &&
          (parsedRouteId == null || parsedRouteId.isEmpty)) {
        throw CatalogFormatException(
          '$variantPath.routeId must not be empty when supplied.',
        );
      }
      final routeId = parsedRouteId ?? id;
      final routeKey = routeId.toLowerCase();
      final priorRouteLabel = routeLabels[routeKey];
      if (priorRouteLabel != null &&
          priorRouteLabel.toLowerCase() != label.toLowerCase()) {
        throw CatalogFormatException(
          '$variantPath.label must match the other formulas in route '
          '"$routeId".',
        );
      }
      routeLabels[routeKey] = label;
      final parsedBatchMultiplier = map.containsKey('batchMultiplier')
          ? _finiteDouble(map['batchMultiplier'])
          : 1.0;
      if (parsedBatchMultiplier == null ||
          parsedBatchMultiplier < 1 ||
          parsedBatchMultiplier.truncateToDouble() != parsedBatchMultiplier) {
        throw CatalogFormatException(
          '$variantPath.batchMultiplier must be a positive integer.',
        );
      }
      final batchMultiplier = parsedBatchMultiplier.toInt();
      if (!routeBatches.add('$routeKey\u0000$batchMultiplier')) {
        throw CatalogFormatException(
          '$path contains duplicate route/batch combination '
          '"$routeId" at ${batchMultiplier}x.',
        );
      }
      final rawIngredients = map['ingredients'];
      if (rawIngredients is! List || rawIngredients.isEmpty) {
        throw CatalogFormatException(
          '$variantPath.ingredients must contain a complete formula.',
        );
      }
      final ingredients = <Ingredient>[
        for (
          var ingredientIndex = 0;
          ingredientIndex < rawIngredients.length;
          ingredientIndex += 1
        )
          _ingredient(
            rawIngredients[ingredientIndex],
            '$variantPath.ingredients[$ingredientIndex]',
          ),
      ];
      variants.add(
        RecipeVariant(
          id: id,
          label: label,
          type: _flexibleString(map['type']) ?? fallbackType,
          baseOutput: _finiteDouble(map['baseOutput']) ?? fallbackBaseOutput,
          method: map.containsKey('method')
              ? _flexibleString(map['method'])
              : fallbackMethod,
          ingredients: ingredients,
          outputMinimum:
              _finiteDouble(map['outputMin']) ?? fallbackOutputMinimum,
          outputMaximum:
              _finiteDouble(map['outputMax']) ?? fallbackOutputMaximum,
          routeId: routeId,
          batchMultiplier: batchMultiplier,
        ),
      );
    }
    return variants;
  }

  RecipeRole _recipeRole(Object? value, String path) {
    try {
      return RecipeRole.fromCatalogValue(_flexibleString(value));
    } on FormatException catch (error) {
      throw CatalogFormatException('$path: ${error.message}');
    }
  }

  Ingredient _ingredient(Object? value, String path) {
    final map = _objectMap(value, path);
    final rawOptions = map['options'];
    final options = rawOptions is List
        ? rawOptions.map(_flexibleString).whereType<String>()
        : const <String>[];
    final ratios = <String, double>{};
    final rawRatios = map['substituteRatios'];
    if (rawRatios is Map) {
      for (final entry in rawRatios.entries) {
        final ratio = _finiteDouble(entry.value);
        if (ratio != null) ratios[entry.key.toString()] = ratio;
      }
    }
    return Ingredient(
      name: _flexibleString(map['name']) ?? '',
      quantity: _finiteDouble(map['qty']) ?? 0,
      options: options,
      substituteGroup: _flexibleString(map['substituteGroup']),
      substituteRatios: ratios,
    );
  }

  void _verifyProductionCounts(CatalogSnapshot snapshot) {
    final actual = <String, int>{
      'alchemy items': snapshot.alchemy.items.length,
      'alchemy craftable': snapshot.alchemy.auditedCraftableCount,
      'alchemy ingredients': snapshot.alchemy.ingredientRowCount,
      'cooking items': snapshot.cooking.items.length,
      'cooking craftable': snapshot.cooking.auditedCraftableCount,
      'cooking ingredients': snapshot.cooking.ingredientRowCount,
      'processing items': snapshot.processing.items.length,
      'processing craftable': snapshot.processing.auditedCraftableCount,
      'processing ingredients': snapshot.processing.ingredientRowCount,
      'total items': snapshot.totalItemCount,
      'total ingredients': snapshot.totalIngredientRowCount,
      'case collisions': snapshot.collisions.length,
    };
    const expected = <String, int>{
      'alchemy items': 355,
      'alchemy craftable': 107,
      'alchemy ingredients': 449,
      'cooking items': 609,
      'cooking craftable': 172,
      'cooking ingredients': 658,
      'processing items': 658,
      'processing craftable': 649,
      'processing ingredients': 1684,
      'total items': 1622,
      'total ingredients': 2791,
      'case collisions': 20,
    };
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) {
        throw CatalogFormatException(
          '${entry.key} expected ${entry.value}, found ${actual[entry.key]}.',
        );
      }
    }
  }
}

Map<String, Object?> _objectMap(Object? value, String path) {
  if (value is! Map) {
    throw CatalogFormatException('$path must be a JSON object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return <String, String>{};
  return value.map(
    (key, item) => MapEntry(key.toString(), _flexibleString(item) ?? ''),
  );
}

Map<String, String> _searchAliasMap(Object? value) {
  if (value is! Map) return <String, String>{};
  return value.map((key, item) {
    final terms = item is Iterable
        ? item
              .map(_flexibleString)
              .whereType<String>()
              .map((term) => term.trim())
              .where((term) => term.isNotEmpty)
        : <String>[
            if (_flexibleString(item)?.trim() case final term?
                when term.isNotEmpty)
              term,
          ];
    return MapEntry(key.toString(), terms.join('; '));
  });
}

String? _flexibleString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return null;
}

double? _finiteDouble(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : null;
}

void _findCaseCollisions(
  Object? value,
  String path,
  List<CaseCollision> output,
) {
  if (value is Map) {
    final groups = <String, List<MapEntry<Object?, Object?>>>{};
    for (final entry in value.entries) {
      groups
          .putIfAbsent(entry.key.toString().toLowerCase(), () => [])
          .add(entry);
    }
    for (final group in groups.values.where((entries) => entries.length > 1)) {
      final encodedValues = group
          .map(
            (entry) => path == r'$.marketIds'
                ? _flexibleString(entry.value)
                : jsonEncode(entry.value),
          )
          .toSet();
      output.add(
        CaseCollision(
          jsonPath: path,
          spellings: group.map((entry) => entry.key.toString()),
          valuesEqual: encodedValues.length == 1,
        ),
      );
    }
    for (final entry in value.entries) {
      _findCaseCollisions(entry.value, '$path.${entry.key}', output);
    }
  } else if (value is List) {
    for (var index = 0; index < value.length; index++) {
      _findCaseCollisions(value[index], '$path[$index]', output);
    }
  }
}
