import 'dart:convert';
import 'dart:typed_data';

import '../models/catalog_models.dart';
import '../models/craft_mode.dart';
import 'planner_state.dart';

class PlannerStateFormatException implements Exception {
  const PlannerStateFormatException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'PlannerStateFormatException at $path: $message';
}

class PlannerStateJsonCodec {
  const PlannerStateJsonCodec();

  String encode(PlannerState state) => jsonEncode(state.toJson());

  PlannerState decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on Object catch (error) {
      throw PlannerStateFormatException(r'$', 'Invalid JSON: $error');
    }
    final root = _object(decoded, r'$');
    final reader = _NativeReader(root, r'$');
    final schemaVersion = _integer(
      reader.take('schemaVersion'),
      r'$.schemaVersion',
    );
    if (schemaVersion != 1) {
      throw PlannerStateFormatException(
        r'$.schemaVersion',
        'Unsupported native schema version $schemaVersion.',
      );
    }
    final applicationVersion = _string(
      reader.take('applicationVersion'),
      r'$.applicationVersion',
    );
    final writtenAt = DateTime.tryParse(
      _string(
        reader.take('lastSuccessfulWriteUtc'),
        r'$.lastSuccessfulWriteUtc',
      ),
    );
    if (writtenAt == null) {
      throw const PlannerStateFormatException(
        r'$.lastSuccessfulWriteUtc',
        'Expected an ISO-8601 timestamp.',
      );
    }
    final originValue = reader.takeOptional('origin');
    final afkWeightProfileValue = reader.takeOptional('afkWeightProfile');
    return PlannerState(
      schemaVersion: schemaVersion,
      applicationVersion: applicationVersion,
      lastSuccessfulWriteUtc: writtenAt.toUtc(),
      origin: originValue == null ? null : _origin(originValue, r'$.origin'),
      activeMode: _mode(reader.take('activeMode'), r'$.activeMode'),
      alchemy: _modeState(reader.take('alchemy'), r'$.alchemy'),
      cooking: _modeState(reader.take('cooking'), r'$.cooking'),
      processing: _modeState(reader.take('processing'), r'$.processing'),
      processingYields: _numberMap(
        reader.take('processingYields'),
        r'$.processingYields',
      ),
      marketTax: _marketTax(reader.take('marketTax'), r'$.marketTax'),
      afkWeightProfile: afkWeightProfileValue == null
          ? AfkWeightProfile()
          : _afkWeightProfile(afkWeightProfileValue, r'$.afkWeightProfile'),
      showDeleteTools: _boolean(
        reader.take('showDeleteTools'),
        r'$.showDeleteTools',
      ),
      extensions: reader.extensions(),
    );
  }

  void validateBytes(Uint8List bytes) {
    try {
      decode(utf8.decode(bytes, allowMalformed: false));
    } on PlannerStateFormatException {
      rethrow;
    } on Object catch (error) {
      throw PlannerStateFormatException(r'$', 'Invalid UTF-8 state: $error');
    }
  }

  MigrationOrigin _origin(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    final versionsObject = _object(
      reader.take('sourceModeVersions'),
      '$path.sourceModeVersions',
    );
    final knownModeKeys = CraftMode.values.map((mode) => mode.key).toSet();
    for (final key in versionsObject.keys) {
      if (!knownModeKeys.contains(key)) {
        throw PlannerStateFormatException(
          '$path.sourceModeVersions.$key',
          'Unknown craft mode version key "$key".',
        );
      }
    }
    final versions = <CraftMode, int>{};
    for (final mode in CraftMode.values) {
      versions[mode] = _integer(
        versionsObject[mode.key],
        '$path.sourceModeVersions.${mode.key}',
      );
    }
    final migratedAt = DateTime.tryParse(
      _string(reader.take('migratedAtUtc'), '$path.migratedAtUtc'),
    );
    if (migratedAt == null) {
      throw PlannerStateFormatException(
        '$path.migratedAtUtc',
        'Expected an ISO-8601 timestamp.',
      );
    }
    final result = MigrationOrigin(
      sourceKind: _string(reader.take('sourceKind'), '$path.sourceKind'),
      sourceVersion: _integer(
        reader.take('sourceVersion'),
        '$path.sourceVersion',
      ),
      sourceModeVersions: versions,
      sourceSha256: _string(reader.take('sourceSha256'), '$path.sourceSha256'),
      sourceByteCount: _integer(
        reader.take('sourceByteCount'),
        '$path.sourceByteCount',
      ),
      migratedAtUtc: migratedAt.toUtc(),
      archiveRelativePath: _nullableString(
        reader.takeOptional('archiveRelativePath'),
        '$path.archiveRelativePath',
      ),
    );
    reader.rejectUnknown();
    return result;
  }

  ModeState _modeState(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    final recipeVariantChoicesValue = reader.takeOptional(
      'recipeVariantChoices',
    );
    final afkCraftProgressValue = reader.takeOptional('afkCraftProgress');
    return ModeState(
      target: _string(reader.take('target'), '$path.target'),
      want: _integer(reader.take('want'), '$path.want'),
      bonusTarget: _string(reader.take('bonusTarget'), '$path.bonusTarget'),
      bonusWant: _integer(reader.take('bonusWant'), '$path.bonusWant'),
      inventory: _numberMap(reader.take('inventory'), '$path.inventory'),
      view: _string(reader.take('view'), '$path.view'),
      recipeEdits: _recipeEdits(
        reader.take('recipeEdits'),
        '$path.recipeEdits',
      ),
      iconAliases: _stringMap(reader.take('iconAliases'), '$path.iconAliases'),
      customIcons: _customIcons(
        reader.take('customIcons'),
        '$path.customIcons',
      ),
      ingredientMeta: _ingredientMetadataMap(
        reader.take('ingredientMeta'),
        '$path.ingredientMeta',
      ),
      customCategories: _stringList(
        reader.take('customCategories'),
        '$path.customCategories',
      ),
      substituteChoices: _stringMap(
        reader.take('substituteChoices'),
        '$path.substituteChoices',
      ),
      ingredientGrades: _ingredientGradeMap(
        reader.take('ingredientGrades'),
        '$path.ingredientGrades',
      ),
      recipeVariantChoices: recipeVariantChoicesValue == null
          ? const <String, String>{}
          : _stringMap(recipeVariantChoicesValue, '$path.recipeVariantChoices'),
      favoriteRecipes: _stringList(
        reader.take('favoriteRecipes'),
        '$path.favoriteRecipes',
      ),
      hiddenItems: _stringList(reader.take('hiddenItems'), '$path.hiddenItems'),
      bookFavoritesOnly: _boolean(
        reader.take('bookFavoritesOnly'),
        '$path.bookFavoritesOnly',
      ),
      bookSearchIngredients: _boolean(
        reader.take('bookSearchIngredients'),
        '$path.bookSearchIngredients',
      ),
      market: _market(reader.take('market'), '$path.market'),
      appearance: _appearance(reader.take('appearance'), '$path.appearance'),
      ignoreTargetInventory: _boolean(
        reader.take('ignoreTargetInventory'),
        '$path.ignoreTargetInventory',
      ),
      ignoreIngredientInventory: _boolean(
        reader.take('ignoreIngredientInventory'),
        '$path.ignoreIngredientInventory',
      ),
      alchemyMastery: _integer(
        reader.take('alchemyMastery'),
        '$path.alchemyMastery',
      ),
      cookingMastery: _integer(
        reader.take('cookingMastery'),
        '$path.cookingMastery',
      ),
      processingMastery: _integer(
        reader.take('processingMastery'),
        '$path.processingMastery',
      ),
      useMassProcessing: _boolean(
        reader.take('useMassProcessing'),
        '$path.useMassProcessing',
      ),
      completedSteps: _stringList(
        reader.take('completedSteps'),
        '$path.completedSteps',
      ),
      afkCraftProgress: afkCraftProgressValue == null
          ? const <String, AfkCraftProgress>{}
          : _afkCraftProgressMap(
              afkCraftProgressValue,
              '$path.afkCraftProgress',
            ),
      compatibility: _compatibility(
        reader.take('compatibility'),
        '$path.compatibility',
      ),
      extensions: reader.extensions(),
    );
  }

  Map<String, AfkCraftProgress> _afkCraftProgressMap(
    Object? value,
    String path,
  ) {
    final source = _object(value, path);
    final result = <String, AfkCraftProgress>{};
    for (final entry in source.entries) {
      final entryPath = '$path.${entry.key}';
      if (entry.key.trim().isEmpty) {
        throw PlannerStateFormatException(
          entryPath,
          'AFK craft progress keys must not be blank.',
        );
      }
      final reader = _NativeReader(_object(entry.value, entryPath), entryPath);
      final stepKey = _nonblankString(
        reader.take('stepKey'),
        '$entryPath.stepKey',
      );
      if (stepKey != entry.key) {
        throw PlannerStateFormatException(
          '$entryPath.stepKey',
          'The stored step key must exactly match its map key.',
        );
      }
      final totalAttempts = _positiveInteger(
        reader.take('totalAttempts'),
        '$entryPath.totalAttempts',
      );
      final completedAttempts = _nonnegativeInteger(
        reader.take('completedAttempts'),
        '$entryPath.completedAttempts',
      );
      if (completedAttempts > totalAttempts) {
        throw PlannerStateFormatException(
          '$entryPath.completedAttempts',
          'Completed attempts cannot exceed total attempts.',
        );
      }
      result[entry.key] = AfkCraftProgress(
        stepKey: stepKey,
        targetName: _nonblankString(
          reader.take('targetName'),
          '$entryPath.targetName',
        ),
        targetAmount: _positiveInteger(
          reader.take('targetAmount'),
          '$entryPath.targetAmount',
        ),
        recipeName: _nonblankString(
          reader.take('recipeName'),
          '$entryPath.recipeName',
        ),
        planSignature: _nonblankString(
          reader.take('planSignature'),
          '$entryPath.planSignature',
        ),
        totalAttempts: totalAttempts,
        attemptsPerRound: _positiveInteger(
          reader.take('attemptsPerRound'),
          '$entryPath.attemptsPerRound',
        ),
        completedAttempts: completedAttempts,
        extensions: reader.extensions(),
      );
    }
    return result;
  }

  LegacyModeState _compatibility(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    return LegacyModeState(
      sourceVersion: _integer(
        reader.take('sourceVersion'),
        '$path.sourceVersion',
      ),
      done: _object(reader.take('done'), '$path.done'),
      planSearch: _string(reader.take('planSearch'), '$path.planSearch'),
      bookSearchRelatedItems: _boolean(
        reader.take('bookSearchRelatedItems'),
        '$path.bookSearchRelatedItems',
      ),
      alchemyYield: _number(reader.take('alchemyYield'), '$path.alchemyYield'),
      extensions: reader.extensions(),
    );
  }

  Map<String, RecipeState?> _recipeEdits(Object? value, String path) {
    final object = _object(value, path);
    return {
      for (final entry in object.entries)
        entry.key: entry.value == null
            ? null
            : _recipe(entry.value, '$path.${entry.key}'),
    };
  }

  RecipeState _recipe(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    final ingredientsValue = reader.take('ingredients');
    if (ingredientsValue is! List) {
      throw PlannerStateFormatException(
        '$path.ingredients',
        'Expected an array.',
      );
    }
    return RecipeState(
      type: _string(reader.take('type'), '$path.type'),
      baseOutput: _number(reader.take('baseOutput'), '$path.baseOutput'),
      role: _nullableRecipeRole(
        reader.takeOptional('recipeRole'),
        '$path.recipeRole',
      ),
      group: _nullableString(reader.takeOptional('group'), '$path.group'),
      method: _nullableString(reader.takeOptional('method'), '$path.method'),
      ingredients: [
        for (var index = 0; index < ingredientsValue.length; index++)
          _ingredient(ingredientsValue[index], '$path.ingredients[$index]'),
      ],
      marketId: _flexibleId(reader.takeOptional('marketId'), '$path.marketId'),
      sourceNote: _nullableString(
        reader.takeOptional('sourceNote'),
        '$path.sourceNote',
      ),
      vendor: _nullableString(reader.takeOptional('vendor'), '$path.vendor'),
      location: _nullableString(
        reader.takeOptional('location'),
        '$path.location',
      ),
      npcPrice: _number(reader.take('npcPrice'), '$path.npcPrice'),
      qualityBase: _nullableString(
        reader.takeOptional('qualityBase'),
        '$path.qualityBase',
      ),
      qualityGrade: _nullableString(
        reader.takeOptional('qualityGrade'),
        '$path.qualityGrade',
      ),
      outputMinimum: _nullableNumber(
        reader.takeOptional('outputMinimum'),
        '$path.outputMinimum',
      ),
      outputMaximum: _nullableNumber(
        reader.takeOptional('outputMaximum'),
        '$path.outputMaximum',
      ),
      extensions: reader.extensions(),
    );
  }

  RecipeRole? _nullableRecipeRole(Object? value, String path) {
    if (value == null) return null;
    final raw = _string(value, path);
    try {
      return RecipeRole.fromCatalogValue(raw);
    } on FormatException catch (error) {
      throw PlannerStateFormatException(path, error.message);
    }
  }

  IngredientState _ingredient(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    return IngredientState(
      name: _string(reader.take('name'), '$path.name'),
      quantity: _number(reader.take('quantity'), '$path.quantity'),
      options: _stringList(reader.take('options'), '$path.options'),
      substituteGroup: _nullableString(
        reader.takeOptional('substituteGroup'),
        '$path.substituteGroup',
      ),
      substituteRatios: _numberMap(
        reader.take('substituteRatios'),
        '$path.substituteRatios',
      ),
      extensions: reader.extensions(),
    );
  }

  Map<String, CustomIconReference> _customIcons(Object? value, String path) {
    final object = _object(value, path);
    return {
      for (final entry in object.entries)
        entry.key: _customIcon(entry.value, '$path.${entry.key}'),
    };
  }

  CustomIconReference _customIcon(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    final result = CustomIconReference(
      relativePath: _string(reader.take('relativePath'), '$path.relativePath'),
      sha256: _string(reader.take('sha256'), '$path.sha256'),
      mediaType: _string(reader.take('mediaType'), '$path.mediaType'),
      byteCount: _integer(reader.take('byteCount'), '$path.byteCount'),
      width: _nullableInteger(reader.takeOptional('width'), '$path.width'),
      height: _nullableInteger(reader.takeOptional('height'), '$path.height'),
    );
    reader.rejectUnknown();
    return result;
  }

  Map<String, IngredientMetadata> _ingredientMetadataMap(
    Object? value,
    String path,
  ) {
    final object = _object(value, path);
    return {
      for (final entry in object.entries)
        entry.key: _ingredientMetadata(entry.value, '$path.${entry.key}'),
    };
  }

  IngredientMetadata _ingredientMetadata(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    return IngredientMetadata(
      category: _nullableString(
        reader.takeOptional('category'),
        '$path.category',
      ),
      npcPrice: _number(reader.take('npcPrice'), '$path.npcPrice'),
      sourceNote: _nullableString(
        reader.takeOptional('sourceNote'),
        '$path.sourceNote',
      ),
      searchKeywords: _nullableString(
        reader.takeOptional('searchKeywords'),
        '$path.searchKeywords',
      ),
      vendor: _nullableString(reader.takeOptional('vendor'), '$path.vendor'),
      location: _nullableString(
        reader.takeOptional('location'),
        '$path.location',
      ),
      marketId: _flexibleId(reader.takeOptional('marketId'), '$path.marketId'),
      qualityBase: _nullableString(
        reader.takeOptional('qualityBase'),
        '$path.qualityBase',
      ),
      qualityTier: _nullableString(
        reader.takeOptional('qualityTier'),
        '$path.qualityTier',
      ),
      extensions: reader.extensions(),
    );
  }

  MarketState _market(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    final unlistedItemNames = reader.takeOptional('unlistedItemNames');
    final tradeMarketIds = reader.takeOptional('tradeMarketIds');
    final totalTrades = reader.takeOptional('totalTrades');
    final tradeObservedAt = reader.takeOptional('tradeObservedAt');
    final observedDailyTrades = reader.takeOptional('observedDailyTrades');
    final tradeObservationHours = reader.takeOptional('tradeObservationHours');
    final lastSoldAtEpochSeconds = reader.takeOptional(
      'lastSoldAtEpochSeconds',
    );
    return MarketState(
      prices: _numberMap(reader.take('prices'), '$path.prices'),
      stock: _numberMap(reader.take('stock'), '$path.stock'),
      tradeMarketIds: tradeMarketIds == null
          ? const <String, String>{}
          : _stringMap(tradeMarketIds, '$path.tradeMarketIds'),
      totalTrades: totalTrades == null
          ? const <String, int>{}
          : _nonnegativeIntegerMap(totalTrades, '$path.totalTrades'),
      tradeObservedAt: tradeObservedAt == null
          ? const <String, int>{}
          : _nonnegativeIntegerMap(tradeObservedAt, '$path.tradeObservedAt'),
      observedDailyTrades: observedDailyTrades == null
          ? const <String, double>{}
          : _nonnegativeNumberMap(
              observedDailyTrades,
              '$path.observedDailyTrades',
            ),
      tradeObservationHours: tradeObservationHours == null
          ? const <String, double>{}
          : _nonnegativeNumberMap(
              tradeObservationHours,
              '$path.tradeObservationHours',
            ),
      lastSoldAtEpochSeconds: lastSoldAtEpochSeconds == null
          ? const <String, int>{}
          : _nonnegativeIntegerMap(
              lastSoldAtEpochSeconds,
              '$path.lastSoldAtEpochSeconds',
            ),
      unlistedItemNames: unlistedItemNames == null
          ? const <String>[]
          : _stringList(unlistedItemNames, '$path.unlistedItemNames'),
      search: _string(reader.take('search'), '$path.search'),
      sort: _string(reader.take('sort'), '$path.sort'),
      amount: _integer(reader.take('amount'), '$path.amount'),
      selected: _string(reader.take('selected'), '$path.selected'),
      fetchedAt: _integer(reader.take('fetchedAt'), '$path.fetchedAt'),
      region: _string(reader.take('region'), '$path.region'),
      extensions: reader.extensions(),
    );
  }

  MarketTax _marketTax(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    return MarketTax(
      enabled: _boolean(reader.take('enabled'), '$path.enabled'),
      valuePack: _boolean(reader.take('valuePack'), '$path.valuePack'),
      merchantRing: _boolean(reader.take('merchantRing'), '$path.merchantRing'),
      familyFameBonus: _number(
        reader.take('familyFameBonus'),
        '$path.familyFameBonus',
      ),
      extensions: reader.extensions(),
    );
  }

  AfkWeightProfile _afkWeightProfile(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    final featheryStepsLevel = _nonnegativeInteger(
      reader.take('featheryStepsLevel'),
      '$path.featheryStepsLevel',
    );
    if (featheryStepsLevel > 5) {
      throw PlannerStateFormatException(
        '$path.featheryStepsLevel',
        'Expected an integer from 0 through 5.',
      );
    }
    return AfkWeightProfile(
      maximumWeightLt: _nonnegativeNumber(
        reader.take('maximumWeightLt'),
        '$path.maximumWeightLt',
      ),
      currentCarriedWeightLt: _nonnegativeNumber(
        reader.take('currentCarriedWeightLt'),
        '$path.currentCarriedWeightLt',
      ),
      safetyBufferLt: _nonnegativeNumber(
        reader.take('safetyBufferLt'),
        '$path.safetyBufferLt',
      ),
      featheryStepsLevel: featheryStepsLevel,
      extensions: reader.extensions(),
    );
  }

  AppearanceSettings _appearance(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    final presetsValue = reader.take('presets');
    if (presetsValue is! List) {
      throw PlannerStateFormatException('$path.presets', 'Expected an array.');
    }
    return AppearanceSettings(
      background: _string(reader.take('background'), '$path.background'),
      liveBackdrop: _boolean(reader.take('liveBackdrop'), '$path.liveBackdrop'),
      motionIntensity: _number(
        reader.take('motionIntensity'),
        '$path.motionIntensity',
      ),
      motionSpeed: _number(reader.take('motionSpeed'), '$path.motionSpeed'),
      particleStyle: _string(
        reader.take('particleStyle'),
        '$path.particleStyle',
      ),
      particleDensity: _number(
        reader.take('particleDensity'),
        '$path.particleDensity',
      ),
      particleOpacity: _number(
        reader.take('particleOpacity'),
        '$path.particleOpacity',
      ),
      particleMinSize: _number(
        reader.take('particleMinSize'),
        '$path.particleMinSize',
      ),
      particleMaxSize: _number(
        reader.take('particleMaxSize'),
        '$path.particleMaxSize',
      ),
      particleSize: _number(reader.take('particleSize'), '$path.particleSize'),
      particleBlur: _number(reader.take('particleBlur'), '$path.particleBlur'),
      particleCustomColor: _boolean(
        reader.take('particleCustomColor'),
        '$path.particleCustomColor',
      ),
      particleHue: _number(reader.take('particleHue'), '$path.particleHue'),
      particleRainbow: _boolean(
        reader.take('particleRainbow'),
        '$path.particleRainbow',
      ),
      particleNeon: _boolean(reader.take('particleNeon'), '$path.particleNeon'),
      buttonEffect: _string(reader.take('buttonEffect'), '$path.buttonEffect'),
      buttonEffectIntensity: _number(
        reader.take('buttonEffectIntensity'),
        '$path.buttonEffectIntensity',
      ),
      buttonEffectSpeed: _number(
        reader.take('buttonEffectSpeed'),
        '$path.buttonEffectSpeed',
      ),
      buttonEffectBlur: _number(
        reader.take('buttonEffectBlur'),
        '$path.buttonEffectBlur',
      ),
      buttonEffectActiveOnly: _boolean(
        reader.take('buttonEffectActiveOnly'),
        '$path.buttonEffectActiveOnly',
      ),
      buttonEffectCustomColor: _boolean(
        reader.take('buttonEffectCustomColor'),
        '$path.buttonEffectCustomColor',
      ),
      buttonEffectHue: _number(
        reader.take('buttonEffectHue'),
        '$path.buttonEffectHue',
      ),
      buttonEffectRainbow: _boolean(
        reader.take('buttonEffectRainbow'),
        '$path.buttonEffectRainbow',
      ),
      buttonEffectNeon: _boolean(
        reader.take('buttonEffectNeon'),
        '$path.buttonEffectNeon',
      ),
      accentHue: _number(reader.take('accentHue'), '$path.accentHue'),
      rainbow: _boolean(reader.take('rainbow'), '$path.rainbow'),
      neon: _boolean(reader.take('neon'), '$path.neon'),
      backdropBlur: _number(reader.take('backdropBlur'), '$path.backdropBlur'),
      tabFade: _boolean(reader.take('tabFade'), '$path.tabFade'),
      tabTransition: _string(
        reader.take('tabTransition'),
        '$path.tabTransition',
      ),
      tabTransitionSpeed: _tabTransitionSpeed(
        reader.takeOptional('tabTransitionSpeed'),
        '$path.tabTransitionSpeed',
      ),
      presets: [
        for (var index = 0; index < presetsValue.length; index++)
          presetsValue[index] == null
              ? null
              : _preset(presetsValue[index], '$path.presets[$index]'),
      ],
      extensions: reader.extensions(),
    );
  }

  AppearancePreset _preset(Object? value, String path) {
    final reader = _NativeReader(_object(value, path), path);
    return AppearancePreset(
      name: _string(reader.take('name'), '$path.name'),
      settings: _appearance(reader.take('settings'), '$path.settings'),
      extensions: reader.extensions(),
    );
  }
}

class _NativeReader {
  _NativeReader(this.source, this.path);

  final Map<String, Object?> source;
  final String path;
  final Set<String> _consumed = {};

  Object? take(String name) {
    if (!source.containsKey(name)) {
      throw PlannerStateFormatException(
        '$path.$name',
        'Required field is absent.',
      );
    }
    _consumed.add(name);
    return source[name];
  }

  Object? takeOptional(String name) {
    if (!source.containsKey(name)) return null;
    _consumed.add(name);
    return source[name];
  }

  Map<String, Object?> extensions() {
    final result = <String, Object?>{};
    final explicit = takeOptional('extensions');
    if (explicit != null) result.addAll(_object(explicit, '$path.extensions'));
    for (final entry in source.entries) {
      if (!_consumed.contains(entry.key)) result[entry.key] = entry.value;
    }
    return result;
  }

  void rejectUnknown() {
    for (final key in source.keys) {
      if (!_consumed.contains(key)) {
        throw PlannerStateFormatException(
          '$path.$key',
          'Unknown field cannot be preserved by this object.',
        );
      }
    }
  }
}

String _tabTransitionSpeed(Object? value, String path) {
  if (value == null) return 'normal';
  final normalized = _string(value, path).trim().toLowerCase();
  return const {'slow', 'normal', 'fast'}.contains(normalized)
      ? normalized
      : 'normal';
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map) {
    throw PlannerStateFormatException(path, 'Expected an object.');
  }
  return value.map((key, nested) {
    if (key is! String) {
      throw PlannerStateFormatException(path, 'Object keys must be strings.');
    }
    return MapEntry(key, nested);
  });
}

String _string(Object? value, String path) {
  if (value is String) return value;
  throw PlannerStateFormatException(path, 'Expected a string.');
}

String _nonblankString(Object? value, String path) {
  final result = _string(value, path);
  if (result.trim().isEmpty) {
    throw PlannerStateFormatException(path, 'Expected a non-blank string.');
  }
  return result;
}

String? _nullableString(Object? value, String path) {
  if (value == null) return null;
  return _string(value, path);
}

String? _flexibleId(Object? value, String path) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is bool || value is int) return value.toString();
  if (value is double && value.isFinite) return value.toString();
  throw PlannerStateFormatException(path, 'Expected a flexible string ID.');
}

bool _boolean(Object? value, String path) {
  if (value is bool) return value;
  throw PlannerStateFormatException(path, 'Expected a boolean.');
}

int _integer(Object? value, String path) {
  if (value is int) return value;
  throw PlannerStateFormatException(path, 'Expected an integer.');
}

int? _nullableInteger(Object? value, String path) =>
    value == null ? null : _integer(value, path);

double _number(Object? value, String path) {
  if (value is num && value.toDouble().isFinite) return value.toDouble();
  throw PlannerStateFormatException(path, 'Expected a finite number.');
}

double _nonnegativeNumber(Object? value, String path) {
  final result = _number(value, path);
  if (result < 0) {
    throw PlannerStateFormatException(path, 'Expected a nonnegative number.');
  }
  return result;
}

double? _nullableNumber(Object? value, String path) =>
    value == null ? null : _number(value, path);

CraftMode _mode(Object? value, String path) {
  final key = _string(value, path);
  for (final mode in CraftMode.values) {
    if (mode.key == key) return mode;
  }
  throw PlannerStateFormatException(path, 'Unknown craft mode "$key".');
}

Map<String, double> _numberMap(Object? value, String path) {
  final source = _object(value, path);
  return {
    for (final entry in source.entries)
      entry.key: _number(entry.value, '$path.${entry.key}'),
  };
}

Map<String, double> _nonnegativeNumberMap(Object? value, String path) {
  final result = _numberMap(value, path);
  for (final entry in result.entries) {
    if (entry.value < 0) {
      throw PlannerStateFormatException(
        '$path.${entry.key}',
        'Expected a nonnegative number.',
      );
    }
  }
  return result;
}

Map<String, int> _nonnegativeIntegerMap(Object? value, String path) {
  final source = _object(value, path);
  return {
    for (final entry in source.entries)
      entry.key: _nonnegativeInteger(entry.value, '$path.${entry.key}'),
  };
}

int _nonnegativeInteger(Object? value, String path) {
  final result = _integer(value, path);
  if (result < 0) {
    throw PlannerStateFormatException(path, 'Expected a nonnegative integer.');
  }
  return result;
}

int _positiveInteger(Object? value, String path) {
  final result = _integer(value, path);
  if (result <= 0) {
    throw PlannerStateFormatException(path, 'Expected a positive integer.');
  }
  return result;
}

Map<String, String> _stringMap(Object? value, String path) {
  final source = _object(value, path);
  return {
    for (final entry in source.entries)
      entry.key: _string(entry.value, '$path.${entry.key}'),
  };
}

Map<String, String> _ingredientGradeMap(Object? value, String path) {
  final source = _stringMap(value, path);
  const recognized = {'normal', 'high', 'special', 'blue'};
  return {
    for (final entry in source.entries)
      entry.key: switch (entry.value.trim().toLowerCase()) {
        final normalized when recognized.contains(normalized) => normalized,
        _ => entry.value,
      },
  };
}

List<String> _stringList(Object? value, String path) {
  if (value is! List) {
    throw PlannerStateFormatException(path, 'Expected an array.');
  }
  return [
    for (var index = 0; index < value.length; index++)
      _string(value[index], '$path[$index]'),
  ];
}
