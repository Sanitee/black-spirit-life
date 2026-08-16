import 'dart:convert';

import '../../domain/migration/avalonia_v1_migration.dart';
import '../../domain/migration/migration_report.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/state/inventory_storage.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/planner_state_json_codec.dart';
import '../../domain/state/state_copy.dart';

typedef PortableIconExporter = String Function(CustomIconReference icon);
typedef PortableIconImporter =
    CustomIconReference Function(PendingCustomIcon icon);

class PortableFormatException implements Exception {
  const PortableFormatException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'PortableFormatException at $path: $message';
}

class PortableScopes {
  const PortableScopes({
    this.recipes = false,
    this.inventory = false,
    this.plans = false,
    this.choices = false,
    this.market = false,
    this.settings = false,
    this.completed = false,
    this.layout = false,
  });

  const PortableScopes.defaults()
    : recipes = true,
      inventory = false,
      plans = false,
      choices = true,
      market = false,
      settings = true,
      completed = false,
      layout = false;

  const PortableScopes.all()
    : recipes = true,
      inventory = true,
      plans = true,
      choices = true,
      market = true,
      settings = true,
      completed = true,
      layout = true;

  final bool recipes;
  final bool inventory;
  final bool plans;
  final bool choices;
  final bool market;
  final bool settings;
  final bool completed;
  final bool layout;

  bool get any =>
      recipes ||
      inventory ||
      plans ||
      choices ||
      market ||
      settings ||
      completed ||
      layout;

  Map<String, bool> toJson() => {
    'recipes': recipes,
    'inventory': inventory,
    'plans': plans,
    'choices': choices,
    'market': market,
    'settings': settings,
    'completed': completed,
    'layout': layout,
  };

  // Kept beside the JSON projection because these define the wire contract.
  // ignore: sort_constructors_first
  factory PortableScopes.fromJson(Map<String, Object?> source) {
    const names = {
      'recipes',
      'inventory',
      'plans',
      'choices',
      'market',
      'settings',
      'completed',
      'layout',
    };
    final seen = <String>{};
    for (final key in source.keys) {
      final folded = key.toLowerCase();
      if (!names.contains(folded)) {
        throw PortableFormatException(
          r'$.included',
          'Unknown portable scope "$key".',
        );
      }
      if (!seen.add(folded)) {
        throw PortableFormatException(
          r'$.included',
          'Duplicate portable scope "$key".',
        );
      }
      if (source[key] is! bool) {
        throw PortableFormatException(
          r'$.included',
          'Scope "$key" must be a boolean.',
        );
      }
    }
    bool read(String name) {
      for (final entry in source.entries) {
        if (entry.key.toLowerCase() == name) return entry.value as bool;
      }
      return false;
    }

    return PortableScopes(
      recipes: read('recipes'),
      inventory: read('inventory'),
      plans: read('plans'),
      choices: read('choices'),
      market: read('market'),
      settings: read('settings'),
      completed: read('completed'),
      layout: read('layout'),
    );
  }
}

class PortableImportResult {
  const PortableImportResult({
    required this.state,
    required this.scopes,
    required this.legacyFullReplacement,
    required this.migrationReport,
  });

  final PlannerState state;
  final PortableScopes scopes;
  final bool legacyFullReplacement;
  final MigrationReport migrationReport;
}

class PortableV4Codec {
  const PortableV4Codec();

  String export(
    PlannerState state, {
    required PortableScopes scopes,
    bool includeMarketTax = false,
    PortableIconExporter? iconExporter,
  }) {
    final data = <String, Object?>{};
    if (scopes.any) {
      for (final mode in CraftMode.values) {
        data[mode.key] = _exportMode(state.forMode(mode), scopes, iconExporter);
      }
    }
    if (scopes.settings) {
      data['processingYields'] = state.processingYields;
      data['afkWeightProfile'] = _withoutExtensions(
        state.afkWeightProfile.toJson(),
      );
    }
    // Sale-tax modifiers are durable user settings, so the default Settings
    // backup includes them. Keep the explicit Market path for compatibility
    // with older portable exports that grouped the same object with prices.
    if (scopes.settings || (scopes.market && includeMarketTax)) {
      data['marketTax'] = _withoutExtensions(state.marketTax.toJson());
    }
    return jsonEncode({
      'type': 'bdo-tool-portable',
      'version': 4,
      'app': 'BDO Craft Planner',
      'included': scopes.toJson(),
      'data': data,
    });
  }

  PortableImportResult import(
    PlannerState current,
    String source, {
    bool confirmLegacyFullReplacement = false,
    PortableIconImporter? iconImporter,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw PortableFormatException(r'$', 'Invalid JSON: $error');
    }
    final root = _object(decoded, r'$');
    _rejectUnknown(root, const {
      'type',
      'version',
      'app',
      'included',
      'data',
    }, r'$');
    final type = _caseValue(root, 'type');
    if (type != 'bdo-tool-portable') {
      throw const PortableFormatException(
        r'$.type',
        'Unsupported portable type.',
      );
    }
    if (_caseValue(root, 'version') != 4) {
      throw const PortableFormatException(
        r'$.version',
        'Only portable version 4 is supported.',
      );
    }
    if (_caseValue(root, 'app') != 'BDO Craft Planner') {
      throw const PortableFormatException(
        r'$.app',
        'Portable app identity mismatch.',
      );
    }
    final includedValue = _caseValueOptional(root, 'included');
    final includedObject = includedValue == null
        ? <String, Object?>{}
        : _object(includedValue, r'$.included');
    final legacyFullReplacement = includedObject.isEmpty;
    if (legacyFullReplacement && !confirmLegacyFullReplacement) {
      throw const PortableFormatException(
        r'$.included',
        'Legacy whole-mode replacement requires explicit confirmation.',
      );
    }
    final scopes = legacyFullReplacement
        ? const PortableScopes.all()
        : PortableScopes.fromJson(includedObject);
    final data = _object(_caseValue(root, 'data'), r'$.data');
    _rejectUnknown(data, const {
      'alchemy',
      'cooking',
      'processing',
      'processingYields',
      'marketTax',
      'afkWeightProfile',
    }, r'$.data');

    final presentModes = <CraftMode>{};
    final migrationRoot = <String, Object?>{
      'version': 1,
      'activeMode': current.activeMode.key,
    };
    for (final mode in CraftMode.values) {
      final modeValue = _caseValueOptional(data, mode.key);
      if (modeValue != null) {
        _object(modeValue, r'$.data.${mode.key}');
        migrationRoot[mode.key] = modeValue;
        presentModes.add(mode);
      }
    }
    final processingYields = _caseValueOptional(data, 'processingYields');
    if (processingYields != null) {
      migrationRoot['processingYields'] = processingYields;
    }
    final marketTax = _caseValueOptional(data, 'marketTax');
    if (marketTax != null) migrationRoot['marketTax'] = marketTax;
    final afkWeightProfileValue = _caseValueOptional(data, 'afkWeightProfile');
    final afkWeightProfile = afkWeightProfileValue == null
        ? null
        : _portableAfkWeightProfile(
            afkWeightProfileValue,
            r'$.data.afkWeightProfile',
          );

    final defaults = AvaloniaMigrationDefaults(
      applicationVersion: current.applicationVersion,
      modes: {
        for (final mode in CraftMode.values)
          mode: ModeMigrationDefaults(
            target: current.forMode(mode).target,
            want: current.forMode(mode).want,
            alchemyMastery: current.forMode(mode).alchemyMastery,
            cookingMastery: current.forMode(mode).cookingMastery,
            processingMastery: current.forMode(mode).processingMastery,
            alchemyYield: current.forMode(mode).compatibility.alchemyYield,
          ),
      },
    );
    final migrated = AvaloniaV1Migration(
      defaults: defaults,
    ).decodeUtf8(utf8.encode(jsonEncode(migrationRoot)));
    if (!migrated.succeeded || migrated.state == null) {
      final error = migrated.report.diagnostics.firstWhere(
        (diagnostic) =>
            diagnostic.severity == MigrationDiagnosticSeverity.error,
        orElse: () => const MigrationDiagnostic(
          path: r'$.data',
          code: 'invalid-portable-data',
          message: 'Portable data could not be normalized.',
          severity: MigrationDiagnosticSeverity.error,
        ),
      );
      throw PortableFormatException(error.path, error.message);
    }
    if (migrated.pendingCustomIcons.isNotEmpty && iconImporter == null) {
      throw const PortableFormatException(
        r'$.data',
        'Portable custom icons require a validated icon importer.',
      );
    }
    final iconsByMode = <CraftMode, Map<String, CustomIconReference>>{};
    for (final pending in migrated.pendingCustomIcons) {
      (iconsByMode[pending.mode] ??= {})[pending.itemName] = iconImporter!(
        pending,
      );
    }

    var result = current;
    for (final mode in presentModes) {
      var incoming = migrated.state!.forMode(mode);
      if (iconsByMode[mode] case final icons?) {
        incoming = incoming.copyWith(customIcons: icons);
      }
      final next = legacyFullReplacement
          ? incoming
          : _mergeMode(current.forMode(mode), incoming, scopes);
      result = _replaceMode(result, mode, next);
    }
    if (scopes.settings && processingYields != null) {
      result = result.copyWith(
        processingYields: migrated.state!.processingYields,
      );
    }
    if (scopes.settings && afkWeightProfile != null) {
      result = result.copyWith(afkWeightProfile: afkWeightProfile);
    }
    if ((scopes.settings || scopes.market) && marketTax != null) {
      result = result.copyWith(marketTax: migrated.state!.marketTax);
    }
    try {
      const nativeCodec = PlannerStateJsonCodec();
      result = nativeCodec.decode(nativeCodec.encode(result));
    } on PlannerStateFormatException catch (error) {
      throw PortableFormatException(
        error.path,
        'Merged portable state failed native validation: ${error.message}',
      );
    } on Object catch (error) {
      throw PortableFormatException(
        r'$.data',
        'Merged portable state failed native validation: $error',
      );
    }
    return PortableImportResult(
      state: result,
      scopes: scopes,
      legacyFullReplacement: legacyFullReplacement,
      migrationReport: migrated.report,
    );
  }

  Map<String, Object?> _exportMode(
    ModeState state,
    PortableScopes scopes,
    PortableIconExporter? iconExporter,
  ) {
    final output = <String, Object?>{};
    if (scopes.recipes) {
      if (state.customIcons.isNotEmpty && iconExporter == null) {
        throw const PortableFormatException(
          r'$.data',
          'Recipe export requires a custom-icon data URI exporter.',
        );
      }
      output.addAll({
        'recipeEdits': {
          for (final entry in state.recipeEdits.entries)
            entry.key: entry.value == null ? null : _exportRecipe(entry.value!),
        },
        'customIcons': {
          for (final entry in state.customIcons.entries)
            entry.key: iconExporter!(entry.value),
        },
        'iconAliases': state.iconAliases,
        'ingredientMeta': {
          for (final entry in state.ingredientMeta.entries)
            entry.key: _withoutExtensions(entry.value.toJson()),
        },
        'customCategories': state.customCategories,
        'hiddenItems': state.hiddenItems.toList(growable: false),
      });
    }
    if (scopes.inventory) {
      output['inv'] = state.inventory;
      final storage = state.extensions[inventoryStorageExtensionKey];
      if (storage != null) output[inventoryStorageExtensionKey] = storage;
    }
    if (scopes.plans) {
      output.addAll({
        'target': state.target,
        'want': state.want,
        'bonusTarget': state.bonusTarget,
        'bonusWant': state.bonusWant,
      });
    }
    if (scopes.choices) {
      output.addAll({
        'substituteChoices': state.substituteChoices,
        'ingredientGrades': state.ingredientGrades,
        'recipeVariantChoices': state.recipeVariantChoices,
      });
    }
    if (scopes.market) {
      output['market'] = _withoutExtensions(state.market.toJson());
    }
    if (scopes.settings) {
      output.addAll({
        'alchemyMastery': state.alchemyMastery,
        'alchemyYield': state.compatibility.alchemyYield,
        'cookingMastery': state.cookingMastery,
        'processingMastery': state.processingMastery,
        'useMassProcessing': state.useMassProcessing,
        'ignoreTargetInventory': state.ignoreTargetInventory,
        'ignoreIngredientInventory': state.ignoreIngredientInventory,
        'appearance': _withoutExtensions(state.appearance.toJson()),
      });
    }
    if (scopes.completed) {
      output.addAll({
        'completedSteps': state.completedSteps.toList(growable: false),
        'afkCraftProgress': {
          for (final entry in state.afkCraftProgress.entries)
            entry.key: _withoutExtensions(entry.value.toJson()),
        },
        'done': state.compatibility.done,
      });
    }
    if (scopes.layout) {
      output.addAll({
        'view': state.view,
        'bookFavoritesOnly': state.bookFavoritesOnly,
        'bookSearchIngredients': state.bookSearchIngredients,
        'bookSearchRelatedItems': state.compatibility.bookSearchRelatedItems,
      });
    }
    return output;
  }

  Map<String, Object?> _exportRecipe(RecipeState recipe) => {
    'type': recipe.type,
    'baseOutput': recipe.baseOutput,
    if (recipe.group != null) 'group': recipe.group,
    if (recipe.method != null) 'method': recipe.method,
    'ingredients': [
      for (final ingredient in recipe.ingredients)
        {
          'name': ingredient.name,
          'qty': ingredient.quantity,
          'options': ingredient.options,
          if (ingredient.substituteGroup != null)
            'substituteGroup': ingredient.substituteGroup,
          'substituteRatios': ingredient.substituteRatios,
        },
    ],
    if (recipe.marketId != null) 'marketId': recipe.marketId,
    if (recipe.sourceNote != null) 'sourceNote': recipe.sourceNote,
    if (recipe.vendor != null) 'vendor': recipe.vendor,
    if (recipe.location != null) 'location': recipe.location,
    'npcPrice': recipe.npcPrice,
    if (recipe.qualityBase != null) 'qualityBase': recipe.qualityBase,
    if (recipe.qualityGrade != null) 'qualityGrade': recipe.qualityGrade,
    if (recipe.outputMinimum != null) 'outputMin': recipe.outputMinimum,
    if (recipe.outputMaximum != null) 'outputMax': recipe.outputMaximum,
  };
}

ModeState _mergeMode(
  ModeState current,
  ModeState incoming,
  PortableScopes scopes,
) => current.copyWith(
  recipeEdits: scopes.recipes ? incoming.recipeEdits : current.recipeEdits,
  customIcons: scopes.recipes ? incoming.customIcons : current.customIcons,
  iconAliases: scopes.recipes ? incoming.iconAliases : current.iconAliases,
  ingredientMeta: scopes.recipes
      ? incoming.ingredientMeta
      : current.ingredientMeta,
  customCategories: scopes.recipes
      ? incoming.customCategories
      : current.customCategories,
  hiddenItems: scopes.recipes ? incoming.hiddenItems : current.hiddenItems,
  inventory: scopes.inventory ? incoming.inventory : current.inventory,
  extensions: scopes.inventory
      ? _mergeInventoryStorageExtension(current.extensions, incoming.extensions)
      : current.extensions,
  target: scopes.plans ? incoming.target : current.target,
  want: scopes.plans ? incoming.want : current.want,
  bonusTarget: scopes.plans ? incoming.bonusTarget : current.bonusTarget,
  bonusWant: scopes.plans ? incoming.bonusWant : current.bonusWant,
  substituteChoices: scopes.choices
      ? incoming.substituteChoices
      : current.substituteChoices,
  ingredientGrades: scopes.choices
      ? incoming.ingredientGrades
      : current.ingredientGrades,
  recipeVariantChoices: scopes.choices
      ? incoming.recipeVariantChoices
      : current.recipeVariantChoices,
  market: scopes.market ? incoming.market : current.market,
  alchemyMastery: scopes.settings
      ? incoming.alchemyMastery
      : current.alchemyMastery,
  cookingMastery: scopes.settings
      ? incoming.cookingMastery
      : current.cookingMastery,
  processingMastery: scopes.settings
      ? incoming.processingMastery
      : current.processingMastery,
  useMassProcessing: scopes.settings
      ? incoming.useMassProcessing
      : current.useMassProcessing,
  ignoreTargetInventory: scopes.settings
      ? incoming.ignoreTargetInventory
      : current.ignoreTargetInventory,
  ignoreIngredientInventory: scopes.settings
      ? incoming.ignoreIngredientInventory
      : current.ignoreIngredientInventory,
  appearance: scopes.settings ? incoming.appearance : current.appearance,
  completedSteps: scopes.completed
      ? incoming.completedSteps
      : current.completedSteps,
  afkCraftProgress: scopes.completed
      ? incoming.afkCraftProgress
      : current.afkCraftProgress,
  view: scopes.layout ? incoming.view : current.view,
  bookFavoritesOnly: scopes.layout
      ? incoming.bookFavoritesOnly
      : current.bookFavoritesOnly,
  bookSearchIngredients: scopes.layout
      ? incoming.bookSearchIngredients
      : current.bookSearchIngredients,
  compatibility: current.compatibility.copyWith(
    alchemyYield: scopes.settings
        ? incoming.compatibility.alchemyYield
        : current.compatibility.alchemyYield,
    done: scopes.completed
        ? incoming.compatibility.done
        : current.compatibility.done,
    bookSearchRelatedItems: scopes.layout
        ? incoming.compatibility.bookSearchRelatedItems
        : current.compatibility.bookSearchRelatedItems,
  ),
);

Map<String, Object?> _mergeInventoryStorageExtension(
  Map<String, Object?> current,
  Map<String, Object?> incoming,
) {
  final result = Map<String, Object?>.of(current)
    ..remove(inventoryStorageExtensionKey);
  final storage = incoming[inventoryStorageExtensionKey];
  if (storage != null) result[inventoryStorageExtensionKey] = storage;
  return result;
}

PlannerState _replaceMode(
  PlannerState state,
  CraftMode mode,
  ModeState value,
) => switch (mode) {
  CraftMode.alchemy => state.copyWith(alchemy: value),
  CraftMode.cooking => state.copyWith(cooking: value),
  CraftMode.processing => state.copyWith(processing: value),
};

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map) {
    throw PortableFormatException(path, 'Expected an object.');
  }
  return value.map((key, nested) {
    if (key is! String) {
      throw PortableFormatException(path, 'Object keys must be strings.');
    }
    return MapEntry(key, nested);
  });
}

Object? _caseValue(Map<String, Object?> source, String name) {
  final value = _caseValueOptional(source, name);
  if (value == null && !source.keys.any((key) => key.toLowerCase() == name)) {
    throw PortableFormatException(r'$', 'Required field "$name" is absent.');
  }
  return value;
}

Object? _caseValueOptional(Map<String, Object?> source, String name) {
  final matches = source.entries.where(
    (entry) => entry.key.toLowerCase() == name.toLowerCase(),
  );
  if (matches.length > 1) {
    throw PortableFormatException(r'$', 'Duplicate field "$name".');
  }
  return matches.isEmpty ? null : matches.single.value;
}

void _rejectUnknown(
  Map<String, Object?> source,
  Set<String> known,
  String path,
) {
  final foldedKnown = known.map((value) => value.toLowerCase()).toSet();
  for (final key in source.keys) {
    if (!foldedKnown.contains(key.toLowerCase())) {
      throw PortableFormatException(path, 'Unknown field "$key".');
    }
  }
}

Object? _withoutExtensions(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key != 'extensions')
          entry.key.toString(): _withoutExtensions(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_withoutExtensions).toList(growable: false);
  }
  return value;
}

AfkWeightProfile _portableAfkWeightProfile(Object? value, String path) {
  final source = _object(value, path);
  _rejectUnknown(source, const {
    'maximumWeightLt',
    'currentCarriedWeightLt',
    'safetyBufferLt',
    'featheryStepsLevel',
  }, path);
  final featheryStepsLevel = _portableNonnegativeInteger(
    _caseRequiredValue(source, 'featheryStepsLevel', path),
    '$path.featheryStepsLevel',
  );
  if (featheryStepsLevel > 5) {
    throw PortableFormatException(
      '$path.featheryStepsLevel',
      'Expected an integer from 0 through 5.',
    );
  }
  return AfkWeightProfile(
    maximumWeightLt: _portableNonnegativeNumber(
      _caseRequiredValue(source, 'maximumWeightLt', path),
      '$path.maximumWeightLt',
    ),
    currentCarriedWeightLt: _portableNonnegativeNumber(
      _caseRequiredValue(source, 'currentCarriedWeightLt', path),
      '$path.currentCarriedWeightLt',
    ),
    safetyBufferLt: _portableNonnegativeNumber(
      _caseRequiredValue(source, 'safetyBufferLt', path),
      '$path.safetyBufferLt',
    ),
    featheryStepsLevel: featheryStepsLevel,
  );
}

Object? _caseRequiredValue(
  Map<String, Object?> source,
  String name,
  String path,
) {
  final matches = source.entries.where(
    (entry) => entry.key.toLowerCase() == name.toLowerCase(),
  );
  if (matches.length > 1) {
    throw PortableFormatException('$path.$name', 'Duplicate field "$name".');
  }
  if (matches.isEmpty) {
    throw PortableFormatException('$path.$name', 'Required field is absent.');
  }
  return matches.single.value;
}

double _portableNonnegativeNumber(Object? value, String path) {
  if (value is! num || !value.toDouble().isFinite) {
    throw PortableFormatException(path, 'Expected a finite number.');
  }
  final result = value.toDouble();
  if (result < 0) {
    throw PortableFormatException(path, 'Expected a nonnegative number.');
  }
  return result;
}

int _portableNonnegativeInteger(Object? value, String path) {
  if (value is! int) {
    throw PortableFormatException(path, 'Expected an integer.');
  }
  if (value < 0) {
    throw PortableFormatException(path, 'Expected a nonnegative integer.');
  }
  return value;
}
