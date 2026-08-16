import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/craft_mode.dart';
import '../state/planner_state.dart';
import 'migration_report.dart';

const Object _absent = Object();

class ModeMigrationDefaults {
  ModeMigrationDefaults({
    required this.target,
    this.want = 100,
    Map<String, double> inventory = const {},
    Iterable<String> favoriteRecipes = const [],
    this.alchemyMastery = 0,
    this.cookingMastery = 0,
    this.processingMastery = 0,
    this.alchemyYield = 3.2,
  }) : inventory = Map<String, double>.unmodifiable(inventory),
       favoriteRecipes = List<String>.unmodifiable(favoriteRecipes);

  final String target;
  final int want;
  final Map<String, double> inventory;
  final List<String> favoriteRecipes;
  final int alchemyMastery;
  final int cookingMastery;
  final int processingMastery;
  final double alchemyYield;
}

class AvaloniaMigrationDefaults {
  AvaloniaMigrationDefaults({
    required this.applicationVersion,
    required Map<CraftMode, ModeMigrationDefaults> modes,
  }) : modes = Map<CraftMode, ModeMigrationDefaults>.unmodifiable(modes) {
    for (final mode in CraftMode.values) {
      if (!this.modes.containsKey(mode)) {
        throw ArgumentError('Missing migration defaults for ${mode.key}.');
      }
    }
  }

  factory AvaloniaMigrationDefaults.schemaFallback({
    required String applicationVersion,
  }) => AvaloniaMigrationDefaults(
    applicationVersion: applicationVersion,
    modes: {
      CraftMode.alchemy: ModeMigrationDefaults(
        target: 'Harmony Draught - Edania',
        alchemyMastery: 1900,
        alchemyYield: 3.20185,
      ),
      CraftMode.cooking: ModeMigrationDefaults(target: 'Beer'),
      CraftMode.processing: ModeMigrationDefaults(
        target: 'Wheat Flour',
        processingMastery: 2,
      ),
    },
  );

  final String applicationVersion;
  final Map<CraftMode, ModeMigrationDefaults> modes;

  ModeMigrationDefaults forMode(CraftMode mode) => modes[mode]!;
}

class PendingCustomIcon {
  const PendingCustomIcon({
    required this.mode,
    required this.itemName,
    required this.dataUri,
    required this.jsonPath,
  });

  final CraftMode mode;
  final String itemName;
  final String dataUri;
  final String jsonPath;
}

class AvaloniaMigrationResult {
  AvaloniaMigrationResult({
    required this.state,
    required this.report,
    required Iterable<PendingCustomIcon> pendingCustomIcons,
  }) : pendingCustomIcons = List<PendingCustomIcon>.unmodifiable(
         pendingCustomIcons,
       );

  final PlannerState? state;
  final MigrationReport report;
  final List<PendingCustomIcon> pendingCustomIcons;

  bool get succeeded => state != null && !report.hasErrors;
}

class AvaloniaV1Migration {
  AvaloniaV1Migration({required this.defaults, DateTime Function()? utcNow})
    : _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final AvaloniaMigrationDefaults defaults;
  final DateTime Function() _utcNow;

  AvaloniaMigrationResult decodeUtf8(List<int> sourceBytes) {
    final sourceSha256 = sha256.convert(sourceBytes).toString().toUpperCase();
    final report = MigrationReportBuilder();
    final pendingIcons = <PendingCustomIcon>[];
    Object? decoded;

    try {
      decoded = jsonDecode(utf8.decode(sourceBytes, allowMalformed: false));
    } on Object catch (error) {
      report.add(
        path: r'$',
        code: 'invalid-json',
        message: 'The source is not valid UTF-8 JSON: $error',
        severity: MigrationDiagnosticSeverity.error,
      );
      return AvaloniaMigrationResult(
        state: null,
        report: report.build(
          sourceSha256: sourceSha256,
          sourceByteCount: sourceBytes.length,
        ),
        pendingCustomIcons: const [],
      );
    }

    final root = _asObject(decoded);
    if (root == null) {
      report.add(
        path: r'$',
        code: 'required-root',
        message: 'The planner-state root must be a JSON object.',
        severity: MigrationDiagnosticSeverity.error,
      );
      return AvaloniaMigrationResult(
        state: null,
        report: report.build(
          sourceSha256: sourceSha256,
          sourceByteCount: sourceBytes.length,
        ),
        pendingCustomIcons: const [],
      );
    }

    final reader = _ObjectReader(root, r'$', report);
    final sourceVersion = _readVersion(
      reader.take('version'),
      r'$.version',
      report,
    );
    if (sourceVersion > 1) {
      report.add(
        path: r'$.version',
        code: 'unsupported-source-version',
        message:
            'Avalonia state version $sourceVersion is newer than version 1.',
        severity: MigrationDiagnosticSeverity.error,
      );
      return AvaloniaMigrationResult(
        state: null,
        report: report.build(
          sourceSha256: sourceSha256,
          sourceByteCount: sourceBytes.length,
        ),
        pendingCustomIcons: const [],
      );
    }

    final activeMode = _readMode(
      reader.take('activeMode'),
      r'$.activeMode',
      report,
    );
    final sourceModeVersions = <CraftMode, int>{};
    final alchemy = _readModeState(
      reader.take('alchemy'),
      CraftMode.alchemy,
      r'$.alchemy',
      report,
      pendingIcons,
      sourceModeVersions,
    );
    final cooking = _readModeState(
      reader.take('cooking'),
      CraftMode.cooking,
      r'$.cooking',
      report,
      pendingIcons,
      sourceModeVersions,
    );
    final processing = _readModeState(
      reader.take('processing'),
      CraftMode.processing,
      r'$.processing',
      report,
      pendingIcons,
      sourceModeVersions,
    );

    final processingYields = _readProcessingYields(
      reader.take('processingYields'),
      r'$.processingYields',
      report,
    );
    final marketTax = _readMarketTax(
      reader.take('marketTax'),
      r'$.marketTax',
      report,
    );
    final showDeleteTools = _readBool(
      reader.take('showDeleteTools'),
      r'$.showDeleteTools',
      report,
      fallback: false,
    );
    final rootExtensions = reader.extensions();
    final migratedAt = _utcNow().toUtc();

    final state = PlannerState(
      applicationVersion: defaults.applicationVersion,
      lastSuccessfulWriteUtc: DateTime.fromMillisecondsSinceEpoch(
        0,
        isUtc: true,
      ),
      origin: MigrationOrigin(
        sourceKind: 'avalonia',
        sourceVersion: sourceVersion,
        sourceModeVersions: sourceModeVersions,
        sourceSha256: sourceSha256,
        sourceByteCount: sourceBytes.length,
        migratedAtUtc: migratedAt,
      ),
      activeMode: activeMode,
      alchemy: alchemy,
      cooking: cooking,
      processing: processing,
      processingYields: processingYields,
      marketTax: marketTax,
      showDeleteTools: showDeleteTools,
      extensions: rootExtensions,
    );

    report.increment('pendingCustomIcons', pendingIcons.length);
    report.increment('processingYields', processingYields.length);
    return AvaloniaMigrationResult(
      state: state,
      report: report.build(
        sourceSha256: sourceSha256,
        sourceByteCount: sourceBytes.length,
      ),
      pendingCustomIcons: pendingIcons,
    );
  }

  ModeState _readModeState(
    Object? value,
    CraftMode mode,
    String path,
    MigrationReportBuilder report,
    List<PendingCustomIcon> pendingIcons,
    Map<CraftMode, int> sourceModeVersions,
  ) {
    final fallback = defaults.forMode(mode);
    final object = value == _absent || value == null ? null : _asObject(value);
    if (object == null) {
      if (value != _absent && value != null) {
        report.add(
          path: path,
          code: 'invalid-mode-state',
          message: 'Mode state must be an object; bundled defaults were used.',
        );
      } else {
        report.add(
          path: path,
          code: 'missing-mode-state',
          message: 'Mode state was absent; bundled defaults were used.',
          severity: MigrationDiagnosticSeverity.notice,
        );
      }
      sourceModeVersions[mode] = 1;
      return _defaultModeState(mode, fallback);
    }

    final reader = _ObjectReader(object, path, report);
    final sourceVersion = _readVersion(
      reader.take('version'),
      '$path.version',
      report,
    );
    sourceModeVersions[mode] = sourceVersion;
    if (sourceVersion > 1) {
      report.add(
        path: '$path.version',
        code: 'newer-mode-version',
        message:
            'Mode state version $sourceVersion was normalized as version 1.',
      );
    }

    var target = _readFlexibleString(
      reader.take('target'),
      '$path.target',
      report,
      fallback: fallback.target,
    )!;
    if (target.trim().isEmpty) {
      target = fallback.target;
    }
    final want = _readIntAtLeast(
      reader.take('want'),
      '$path.want',
      report,
      fallback: fallback.want,
      minimum: 1,
    );
    var bonusTarget = _readFlexibleString(
      reader.take('bonusTarget'),
      '$path.bonusTarget',
      report,
      fallback: target,
    )!;
    if (bonusTarget.trim().isEmpty) {
      bonusTarget = target;
    }
    final bonusWant = _readIntAtLeast(
      reader.take('bonusWant'),
      '$path.bonusWant',
      report,
      fallback: want,
      minimum: 1,
    );
    final inventory = _readNumberMap(
      reader.take('inv'),
      '$path.inv',
      report,
      allowZero: false,
    );
    final done = _readRawObject(reader.take('done'), '$path.done', report);
    final view = _readView(reader.take('view'), mode, '$path.view', report);
    final planSearch = _readFlexibleString(
      reader.take('planSearch'),
      '$path.planSearch',
      report,
      fallback: '',
    )!;
    final recipeEdits = _readRecipeEdits(
      reader.take('recipeEdits'),
      mode,
      '$path.recipeEdits',
      report,
    );
    final iconAliases = _readStringMap(
      reader.take('iconAliases'),
      '$path.iconAliases',
      report,
    );
    _readPendingCustomIcons(
      reader.take('customIcons'),
      mode,
      '$path.customIcons',
      report,
      pendingIcons,
    );
    final ingredientMeta = _readIngredientMetadataMap(
      reader.take('ingredientMeta'),
      '$path.ingredientMeta',
      report,
    );
    final customCategories = _readNormalizedStringList(
      reader.take('customCategories'),
      '$path.customCategories',
      report,
    );
    final substituteChoices = _readStringMap(
      reader.take('substituteChoices'),
      '$path.substituteChoices',
      report,
    );
    final ingredientGrades = _readGrades(
      reader.take('ingredientGrades'),
      '$path.ingredientGrades',
      report,
    );
    final recipeVariantChoices = _readStringMap(
      reader.take('recipeVariantChoices'),
      '$path.recipeVariantChoices',
      report,
    );
    final favoriteRecipes = _readNormalizedStringList(
      reader.take('favoriteRecipes'),
      '$path.favoriteRecipes',
      report,
    );
    final hiddenItems = _readNormalizedStringList(
      reader.take('hiddenItems'),
      '$path.hiddenItems',
      report,
    );
    final bookFavoritesOnly = _readBool(
      reader.take('bookFavoritesOnly'),
      '$path.bookFavoritesOnly',
      report,
      fallback: false,
    );
    final bookSearchIngredients = _readBool(
      reader.take('bookSearchIngredients'),
      '$path.bookSearchIngredients',
      report,
      fallback: false,
    );
    final bookSearchRelatedItems = _readBool(
      reader.take('bookSearchRelatedItems'),
      '$path.bookSearchRelatedItems',
      report,
      fallback: false,
    );
    final market = _readMarket(
      reader.take('market'),
      target,
      want,
      '$path.market',
      report,
    );
    final appearance = _readAppearance(
      reader.take('appearance'),
      mode,
      '$path.appearance',
      report,
      depth: 0,
    );
    final ignoreTargetInventory = _readBool(
      reader.take('ignoreTargetInventory'),
      '$path.ignoreTargetInventory',
      report,
      fallback: true,
    );
    final ignoreIngredientInventory = _readBool(
      reader.take('ignoreIngredientInventory'),
      '$path.ignoreIngredientInventory',
      report,
      fallback: true,
    );
    final alchemyYield = _readFiniteDouble(
      reader.take('alchemyYield'),
      '$path.alchemyYield',
      report,
      fallback: fallback.alchemyYield,
    );
    final alchemyMastery = _readClampedInt(
      reader.take('alchemyMastery'),
      '$path.alchemyMastery',
      report,
      fallback: fallback.alchemyMastery,
      minimum: 0,
      maximum: 3000,
    );
    final cookingMastery = _readClampedInt(
      reader.take('cookingMastery'),
      '$path.cookingMastery',
      report,
      fallback: fallback.cookingMastery,
      minimum: 0,
      maximum: 3000,
    );
    var processingMastery = _readClampedInt(
      reader.take('processingMastery'),
      '$path.processingMastery',
      report,
      fallback: fallback.processingMastery,
      minimum: 0,
      maximum: 3000,
    );
    if (mode == CraftMode.processing && processingMastery == 0) {
      processingMastery = 2;
      report.add(
        path: '$path.processingMastery',
        code: 'processing-mastery-floor',
        message: 'Processing mastery 0 was normalized to 2.',
        severity: MigrationDiagnosticSeverity.notice,
      );
    }
    final useMassProcessing = _readBool(
      reader.take('useMassProcessing'),
      '$path.useMassProcessing',
      report,
      fallback: false,
    );
    final completedSteps = _readNormalizedStringList(
      reader.take('completedSteps'),
      '$path.completedSteps',
      report,
    );
    final afkCraftProgress = _readAfkCraftProgressMap(
      reader.take('afkCraftProgress'),
      '$path.afkCraftProgress',
      report,
    );
    final extensions = reader.extensions();

    report.increment('${mode.key}.inventory', inventory.length);
    report.increment('${mode.key}.favorites', favoriteRecipes.length);
    report.increment('${mode.key}.recipeEdits', recipeEdits.length);
    report.increment('${mode.key}.ingredientMeta', ingredientMeta.length);
    report.increment('${mode.key}.choices', substituteChoices.length);
    report.increment('${mode.key}.grades', ingredientGrades.length);
    report.increment(
      '${mode.key}.recipeVariantChoices',
      recipeVariantChoices.length,
    );
    report.increment('${mode.key}.marketPrices', market.prices.length);
    report.increment('${mode.key}.marketStock', market.stock.length);
    report.increment('${mode.key}.completed', completedSteps.length);
    report.increment('${mode.key}.afkCraftProgress', afkCraftProgress.length);

    return ModeState(
      target: target,
      want: want,
      bonusTarget: bonusTarget,
      bonusWant: bonusWant,
      inventory: inventory,
      view: view,
      recipeEdits: recipeEdits,
      iconAliases: iconAliases,
      ingredientMeta: ingredientMeta,
      customCategories: customCategories,
      substituteChoices: substituteChoices,
      ingredientGrades: ingredientGrades,
      recipeVariantChoices: recipeVariantChoices,
      favoriteRecipes: favoriteRecipes,
      hiddenItems: hiddenItems,
      bookFavoritesOnly: bookFavoritesOnly,
      bookSearchIngredients: bookSearchIngredients,
      market: market,
      appearance: appearance,
      ignoreTargetInventory: ignoreTargetInventory,
      ignoreIngredientInventory: ignoreIngredientInventory,
      alchemyMastery: alchemyMastery,
      cookingMastery: cookingMastery,
      processingMastery: processingMastery,
      useMassProcessing: useMassProcessing,
      completedSteps: completedSteps,
      afkCraftProgress: afkCraftProgress,
      compatibility: LegacyModeState(
        sourceVersion: sourceVersion,
        done: done,
        planSearch: planSearch,
        bookSearchRelatedItems: bookSearchRelatedItems,
        alchemyYield: alchemyYield,
      ),
      extensions: extensions,
    );
  }

  Map<String, AfkCraftProgress> _readAfkCraftProgressMap(
    Object? value,
    String path,
    MigrationReportBuilder report,
  ) {
    if (value == _absent || value == null) return {};
    final object = _asObject(value);
    if (object == null) {
      _invalidCollection(path, report);
      return {};
    }
    final result = <String, AfkCraftProgress>{};
    for (final entry in object.entries) {
      final key = entry.key.trim();
      final entryPath = '$path.${entry.key}';
      final progressObject = _asObject(entry.value);
      if (key.isEmpty || progressObject == null) {
        report.add(
          path: entryPath,
          code: 'invalid-afk-craft-progress',
          message: 'Invalid AFK craft progress entry was dropped.',
        );
        continue;
      }
      final reader = _ObjectReader(progressObject, entryPath, report);
      final storedStepKey = _readFlexibleString(
        reader.take('stepKey'),
        '$entryPath.stepKey',
        report,
        fallback: key,
      )!.trim();
      if (storedStepKey != key) {
        report.add(
          path: '$entryPath.stepKey',
          code: 'afk-step-key-repaired',
          message: 'The AFK step key was normalized to its containing map key.',
          severity: MigrationDiagnosticSeverity.notice,
        );
      }
      final targetName = _readFlexibleString(
        reader.take('targetName'),
        '$entryPath.targetName',
        report,
      )?.trim();
      final recipeName = _readFlexibleString(
        reader.take('recipeName'),
        '$entryPath.recipeName',
        report,
      )?.trim();
      final planSignature = _readFlexibleString(
        reader.take('planSignature'),
        '$entryPath.planSignature',
        report,
      )?.trim();
      if (targetName == null ||
          targetName.isEmpty ||
          recipeName == null ||
          recipeName.isEmpty ||
          planSignature == null ||
          planSignature.isEmpty) {
        report.add(
          path: entryPath,
          code: 'incomplete-afk-craft-progress',
          message: 'Incomplete AFK craft progress entry was dropped.',
        );
        continue;
      }
      final targetAmount = _readIntAtLeast(
        reader.take('targetAmount'),
        '$entryPath.targetAmount',
        report,
        fallback: 1,
        minimum: 1,
      );
      final totalAttempts = _readIntAtLeast(
        reader.take('totalAttempts'),
        '$entryPath.totalAttempts',
        report,
        fallback: 1,
        minimum: 1,
      );
      final attemptsPerRound = _readIntAtLeast(
        reader.take('attemptsPerRound'),
        '$entryPath.attemptsPerRound',
        report,
        fallback: 1,
        minimum: 1,
      );
      final completedAttempts = _readIntAtLeast(
        reader.take('completedAttempts'),
        '$entryPath.completedAttempts',
        report,
        fallback: 0,
        minimum: 0,
      ).clamp(0, totalAttempts);
      result[key] = AfkCraftProgress(
        stepKey: key,
        targetName: targetName,
        targetAmount: targetAmount,
        recipeName: recipeName,
        planSignature: planSignature,
        totalAttempts: totalAttempts,
        attemptsPerRound: attemptsPerRound,
        completedAttempts: completedAttempts,
        extensions: reader.extensions(),
      );
    }
    return result;
  }

  ModeState _defaultModeState(CraftMode mode, ModeMigrationDefaults value) =>
      ModeState(
        target: value.target,
        want: value.want,
        bonusTarget: value.target,
        bonusWant: value.want,
        inventory: value.inventory,
        favoriteRecipes: value.favoriteRecipes,
        market: MarketState(amount: value.want, selected: value.target),
        appearance: AppearanceSettings.defaultsFor(mode),
        alchemyMastery: value.alchemyMastery,
        cookingMastery: value.cookingMastery,
        processingMastery: mode == CraftMode.processing
            ? value.processingMastery.clamp(2, 3000)
            : value.processingMastery.clamp(0, 3000),
        compatibility: LegacyModeState(alchemyYield: value.alchemyYield),
      );

  Map<String, RecipeState?> _readRecipeEdits(
    Object? value,
    CraftMode mode,
    String path,
    MigrationReportBuilder report,
  ) {
    if (value == _absent || value == null) return {};
    final object = _asObject(value);
    if (object == null) {
      _invalidCollection(path, report);
      return {};
    }
    final result = <String, RecipeState?>{};
    for (final entry in object.entries) {
      if (entry.key.trim().isEmpty) {
        _dropBlankKey(path, report);
        continue;
      }
      if (entry.value == null) {
        result[entry.key] = null;
        continue;
      }
      final recipeObject = _asObject(entry.value);
      if (recipeObject == null) {
        report.add(
          path: '$path.${entry.key}',
          code: 'invalid-recipe',
          message: 'Recipe edit must be an object or null and was dropped.',
        );
        continue;
      }
      result[entry.key] = _readRecipe(
        recipeObject,
        mode,
        '$path.${entry.key}',
        report,
      );
    }
    return result;
  }

  RecipeState _readRecipe(
    Map<String, Object?> object,
    CraftMode mode,
    String path,
    MigrationReportBuilder report,
  ) {
    final reader = _ObjectReader(object, path, report);
    final fallbackType = mode == CraftMode.processing ? 'material' : 'gathered';
    var type = _readFlexibleString(
      reader.take('type'),
      '$path.type',
      report,
      fallback: fallbackType,
    )!;
    final allowedTypes = switch (mode) {
      CraftMode.alchemy => const {
        'alchemy',
        'simple_alchemy',
        'processing',
        'gathered',
      },
      CraftMode.cooking => const {'cooking', 'processing', 'gathered'},
      CraftMode.processing => const {'processing', 'material'},
    };
    if (!allowedTypes.contains(type)) {
      report.add(
        path: '$path.type',
        code: 'invalid-recipe-type',
        message: 'Recipe type "$type" was normalized to "$fallbackType".',
      );
      type = fallbackType;
    }
    var baseOutput = _readFiniteDouble(
      reader.take('baseOutput'),
      '$path.baseOutput',
      report,
      fallback: 1,
    );
    if (baseOutput < .0001) {
      baseOutput = .0001;
      report.add(
        path: '$path.baseOutput',
        code: 'base-output-floor',
        message: 'Recipe base output was raised to 0.0001.',
      );
    }
    final ingredients = _readIngredients(
      reader.take('ingredients'),
      '$path.ingredients',
      report,
    );
    final npcPrice = _readNonNegativeDouble(
      reader.take('npcPrice'),
      '$path.npcPrice',
      report,
    );
    final outputMinimum = _readNullableFiniteDouble(
      reader.take('outputMin'),
      '$path.outputMin',
      report,
    );
    final outputMaximum = _readNullableFiniteDouble(
      reader.take('outputMax'),
      '$path.outputMax',
      report,
    );
    return RecipeState(
      type: type,
      baseOutput: baseOutput,
      group: _readFlexibleString(reader.take('group'), '$path.group', report),
      method: _readFlexibleString(
        reader.take('method'),
        '$path.method',
        report,
      ),
      ingredients: ingredients,
      marketId: _readFlexibleString(
        reader.take('marketId'),
        '$path.marketId',
        report,
      ),
      sourceNote: _readFlexibleString(
        reader.take('sourceNote'),
        '$path.sourceNote',
        report,
      ),
      vendor: _readFlexibleString(
        reader.take('vendor'),
        '$path.vendor',
        report,
      ),
      location: _readFlexibleString(
        reader.take('location'),
        '$path.location',
        report,
      ),
      npcPrice: npcPrice,
      qualityBase: _readFlexibleString(
        reader.take('qualityBase'),
        '$path.qualityBase',
        report,
      ),
      qualityGrade: _readFlexibleString(
        reader.take('qualityGrade'),
        '$path.qualityGrade',
        report,
      ),
      outputMinimum: outputMinimum,
      outputMaximum: outputMaximum,
      extensions: reader.extensions(),
    );
  }

  List<IngredientState> _readIngredients(
    Object? value,
    String path,
    MigrationReportBuilder report,
  ) {
    if (value == _absent || value == null) return [];
    if (value is! List) {
      _invalidCollection(path, report);
      return [];
    }
    final result = <IngredientState>[];
    for (var index = 0; index < value.length; index++) {
      final object = _asObject(value[index]);
      final itemPath = '$path[$index]';
      if (object == null) {
        report.add(
          path: itemPath,
          code: 'invalid-ingredient',
          message: 'Ingredient row must be an object and was dropped.',
        );
        continue;
      }
      final reader = _ObjectReader(object, itemPath, report);
      final name = _readFlexibleString(
        reader.take('name'),
        '$itemPath.name',
        report,
        fallback: '',
      )!;
      final quantity = _readFiniteDouble(
        reader.take('qty'),
        '$itemPath.qty',
        report,
        fallback: 0,
      );
      if (name.trim().isEmpty || quantity <= 0) {
        report.add(
          path: itemPath,
          code: 'invalid-ingredient-row',
          message:
              'Ingredient name and quantity must be positive; row was dropped.',
        );
        continue;
      }
      final options = _readFlexibleStringListPreservingOrder(
        reader.take('options'),
        '$itemPath.options',
        report,
      );
      final ratios = _readNumberMap(
        reader.take('substituteRatios'),
        '$itemPath.substituteRatios',
        report,
        allowZero: false,
      );
      result.add(
        IngredientState(
          name: name,
          quantity: quantity,
          options: options,
          substituteGroup: _readFlexibleString(
            reader.take('substituteGroup'),
            '$itemPath.substituteGroup',
            report,
          ),
          substituteRatios: ratios,
          extensions: reader.extensions(),
        ),
      );
    }
    return result;
  }

  Map<String, IngredientMetadata> _readIngredientMetadataMap(
    Object? value,
    String path,
    MigrationReportBuilder report,
  ) {
    if (value == _absent || value == null) return {};
    final object = _asObject(value);
    if (object == null) {
      _invalidCollection(path, report);
      return {};
    }
    final result = <String, IngredientMetadata>{};
    for (final entry in object.entries) {
      if (entry.key.trim().isEmpty) {
        _dropBlankKey(path, report);
        continue;
      }
      final metadataObject = _asObject(entry.value);
      if (metadataObject == null) {
        report.add(
          path: '$path.${entry.key}',
          code: 'invalid-metadata',
          message: 'Ingredient metadata must be an object and was dropped.',
        );
        continue;
      }
      final reader = _ObjectReader(
        metadataObject,
        '$path.${entry.key}',
        report,
      );
      String? trimmed(String name) => _readFlexibleString(
        reader.take(name),
        '$path.${entry.key}.$name',
        report,
      )?.trim();
      result[entry.key] = IngredientMetadata(
        category: trimmed('category'),
        npcPrice: _readNonNegativeDouble(
          reader.take('npcPrice'),
          '$path.${entry.key}.npcPrice',
          report,
        ),
        sourceNote: trimmed('sourceNote'),
        searchKeywords: trimmed('searchKeywords'),
        vendor: trimmed('vendor'),
        location: trimmed('location'),
        marketId: trimmed('marketId'),
        qualityBase: trimmed('qualityBase'),
        qualityTier: trimmed('qualityTier'),
        extensions: reader.extensions(),
      );
    }
    return result;
  }

  void _readPendingCustomIcons(
    Object? value,
    CraftMode mode,
    String path,
    MigrationReportBuilder report,
    List<PendingCustomIcon> output,
  ) {
    if (value == _absent || value == null) return;
    final object = _asObject(value);
    if (object == null) {
      _invalidCollection(path, report);
      return;
    }
    for (final entry in object.entries) {
      if (entry.key.trim().isEmpty) {
        _dropBlankKey(path, report);
        continue;
      }
      final dataUri = _readFlexibleString(
        entry.value,
        '$path.${entry.key}',
        report,
      );
      if (dataUri == null || dataUri.isEmpty) continue;
      output.add(
        PendingCustomIcon(
          mode: mode,
          itemName: entry.key,
          dataUri: dataUri,
          jsonPath: '$path.${entry.key}',
        ),
      );
    }
  }

  MarketState _readMarket(
    Object? value,
    String target,
    int want,
    String path,
    MigrationReportBuilder report,
  ) {
    final object = value == _absent || value == null ? null : _asObject(value);
    if (object == null) {
      if (value != _absent && value != null) _invalidCollection(path, report);
      return MarketState(amount: want, selected: target);
    }
    final reader = _ObjectReader(object, path, report);
    var selected = _readFlexibleString(
      reader.take('selected'),
      '$path.selected',
      report,
      fallback: target,
    )!;
    if (selected.trim().isEmpty) selected = target;
    var region = _readFlexibleString(
      reader.take('region'),
      '$path.region',
      report,
      fallback: 'eu',
    )!;
    if (region.trim().isEmpty) region = 'eu';
    return MarketState(
      prices: _readNumberMap(
        reader.take('prices'),
        '$path.prices',
        report,
        allowZero: true,
      ),
      stock: _readNumberMap(
        reader.take('stock'),
        '$path.stock',
        report,
        allowZero: true,
      ),
      tradeMarketIds: _readStringMap(
        reader.take('tradeMarketIds'),
        '$path.tradeMarketIds',
        report,
      ),
      totalTrades: _readNonnegativeIntMap(
        reader.take('totalTrades'),
        '$path.totalTrades',
        report,
      ),
      tradeObservedAt: _readNonnegativeIntMap(
        reader.take('tradeObservedAt'),
        '$path.tradeObservedAt',
        report,
      ),
      observedDailyTrades: _readNumberMap(
        reader.take('observedDailyTrades'),
        '$path.observedDailyTrades',
        report,
        allowZero: true,
      ),
      tradeObservationHours: _readNumberMap(
        reader.take('tradeObservationHours'),
        '$path.tradeObservationHours',
        report,
        allowZero: true,
      ),
      lastSoldAtEpochSeconds: _readNonnegativeIntMap(
        reader.take('lastSoldAtEpochSeconds'),
        '$path.lastSoldAtEpochSeconds',
        report,
      ),
      unlistedItemNames: _readNormalizedStringList(
        reader.take('unlistedItemNames'),
        '$path.unlistedItemNames',
        report,
      ),
      search: _readFlexibleString(
        reader.take('search'),
        '$path.search',
        report,
        fallback: '',
      )!,
      sort: _readFlexibleString(
        reader.take('sort'),
        '$path.sort',
        report,
        fallback: 'name',
      )!,
      amount: _readIntAtLeast(
        reader.take('amount'),
        '$path.amount',
        report,
        fallback: want,
        minimum: 1,
      ),
      selected: selected,
      fetchedAt: _readIntAtLeast(
        reader.take('fetchedAt'),
        '$path.fetchedAt',
        report,
        fallback: 0,
        minimum: 0,
      ),
      region: region,
      extensions: reader.extensions(),
    );
  }

  AppearanceSettings _readAppearance(
    Object? value,
    CraftMode mode,
    String path,
    MigrationReportBuilder report, {
    required int depth,
  }) {
    final fallback = AppearanceSettings.defaultsFor(mode);
    final object = value == _absent || value == null ? null : _asObject(value);
    if (object == null) {
      if (value != _absent && value != null) _invalidCollection(path, report);
      return fallback;
    }
    final reader = _ObjectReader(object, path, report);
    final sourceBackground = _readFlexibleString(
      reader.take('background'),
      '$path.background',
      report,
      fallback: fallback.background,
    )!;
    final background = _normalizeBackground(
      sourceBackground,
      fallback.background,
      '$path.background',
      report,
    );
    final particleStyle = _readEnumString(
      reader.take('particleStyle'),
      '$path.particleStyle',
      report,
      fallback: fallback.particleStyle,
      allowed: const {
        'fumes',
        'embers',
        'stars',
        'petals',
        'snow',
        'fireflies',
        'bubbles',
      },
    );
    final buttonEffect = _readEnumString(
      reader.take('buttonEffect'),
      '$path.buttonEffect',
      report,
      fallback: fallback.buttonEffect,
      allowed: const {
        'quiet',
        'glow',
        'orbit',
        'sweep',
        'sigil',
        'embers',
        'frost',
        'fireflies',
      },
    );
    var minimumSize = _readFiniteDouble(
      reader.take('particleMinSize'),
      '$path.particleMinSize',
      report,
      fallback: fallback.particleMinSize,
    );
    var maximumSize = _readFiniteDouble(
      reader.take('particleMaxSize'),
      '$path.particleMaxSize',
      report,
      fallback: fallback.particleMaxSize,
    );
    if (minimumSize <= 0) minimumSize = fallback.particleMinSize;
    if (maximumSize <= 0) maximumSize = fallback.particleMaxSize;
    minimumSize = minimumSize.clamp(.35, 2.2);
    maximumSize = maximumSize.clamp(.35, 2.2);
    if (maximumSize < minimumSize) {
      final oldMinimum = minimumSize;
      minimumSize = maximumSize;
      maximumSize = oldMinimum;
    }
    var particleSize = _readFiniteDouble(
      reader.take('particleSize'),
      '$path.particleSize',
      report,
      fallback: 1,
    );
    if (particleSize <= 0) particleSize = 1;
    particleSize = particleSize.clamp(.2, 2.8);
    final tabFade = _readBool(
      reader.take('tabFade'),
      '$path.tabFade',
      report,
      fallback: true,
    );
    final tabTransition = _normalizeTabTransition(
      _readFlexibleString(
        reader.take('tabTransition'),
        '$path.tabTransition',
        report,
      ),
      tabFade,
    );
    final tabTransitionSpeed = _readEnumString(
      reader.take('tabTransitionSpeed'),
      '$path.tabTransitionSpeed',
      report,
      fallback: 'normal',
      allowed: const {'slow', 'normal', 'fast'},
    );
    final presets = _readPresets(
      reader.take('presets'),
      mode,
      '$path.presets',
      report,
      depth: depth,
    );

    return AppearanceSettings(
      background: background,
      liveBackdrop: _readBool(
        reader.take('liveBackdrop'),
        '$path.liveBackdrop',
        report,
        fallback: true,
      ),
      motionIntensity: _readUnitDouble(
        reader.take('motionIntensity'),
        '$path.motionIntensity',
        report,
        fallback: .42,
      ),
      motionSpeed: _readUnitDouble(
        reader.take('motionSpeed'),
        '$path.motionSpeed',
        report,
        fallback: .42,
      ),
      particleStyle: particleStyle,
      particleDensity: _readUnitDouble(
        reader.take('particleDensity'),
        '$path.particleDensity',
        report,
        fallback: .36,
      ),
      particleOpacity: _readUnitDouble(
        reader.take('particleOpacity'),
        '$path.particleOpacity',
        report,
        fallback: .72,
      ),
      particleMinSize: minimumSize,
      particleMaxSize: maximumSize,
      particleSize: particleSize,
      particleBlur: _readUnitDouble(
        reader.take('particleBlur'),
        '$path.particleBlur',
        report,
        fallback: .12,
      ),
      particleCustomColor: _readBool(
        reader.take('particleCustomColor'),
        '$path.particleCustomColor',
        report,
        fallback: false,
      ),
      particleHue: _readHue(
        reader.take('particleHue'),
        '$path.particleHue',
        report,
        fallback: fallback.particleHue,
      ),
      particleRainbow: _readBool(
        reader.take('particleRainbow'),
        '$path.particleRainbow',
        report,
        fallback: false,
      ),
      particleNeon: _readBool(
        reader.take('particleNeon'),
        '$path.particleNeon',
        report,
        fallback: false,
      ),
      buttonEffect: buttonEffect,
      buttonEffectIntensity: _readUnitDouble(
        reader.take('buttonEffectIntensity'),
        '$path.buttonEffectIntensity',
        report,
        fallback: .62,
      ),
      buttonEffectSpeed: _readUnitDouble(
        reader.take('buttonEffectSpeed'),
        '$path.buttonEffectSpeed',
        report,
        fallback: .48,
      ),
      buttonEffectBlur: _readUnitDouble(
        reader.take('buttonEffectBlur'),
        '$path.buttonEffectBlur',
        report,
        fallback: .08,
      ),
      buttonEffectActiveOnly: _readBool(
        reader.take('buttonEffectActiveOnly'),
        '$path.buttonEffectActiveOnly',
        report,
        fallback: false,
      ),
      buttonEffectCustomColor: _readBool(
        reader.take('buttonEffectCustomColor'),
        '$path.buttonEffectCustomColor',
        report,
        fallback: false,
      ),
      buttonEffectHue: _readHue(
        reader.take('buttonEffectHue'),
        '$path.buttonEffectHue',
        report,
        fallback: fallback.buttonEffectHue,
      ),
      buttonEffectRainbow: _readBool(
        reader.take('buttonEffectRainbow'),
        '$path.buttonEffectRainbow',
        report,
        fallback: false,
      ),
      buttonEffectNeon: _readBool(
        reader.take('buttonEffectNeon'),
        '$path.buttonEffectNeon',
        report,
        fallback: false,
      ),
      accentHue: _readHue(
        reader.take('accentHue'),
        '$path.accentHue',
        report,
        fallback: fallback.accentHue,
      ),
      rainbow: _readBool(
        reader.take('rainbow'),
        '$path.rainbow',
        report,
        fallback: false,
      ),
      neon: _readBool(
        reader.take('neon'),
        '$path.neon',
        report,
        fallback: false,
      ),
      backdropBlur: _readUnitDouble(
        reader.take('backdropBlur'),
        '$path.backdropBlur',
        report,
        fallback: 0,
      ),
      tabFade: tabTransition != 'off',
      tabTransition: tabTransition,
      tabTransitionSpeed: tabTransitionSpeed,
      presets: presets,
      extensions: reader.extensions(),
    );
  }

  List<AppearancePreset?> _readPresets(
    Object? value,
    CraftMode mode,
    String path,
    MigrationReportBuilder report, {
    required int depth,
  }) {
    if (value == _absent || value == null) {
      return List<AppearancePreset?>.filled(6, null);
    }
    if (value is! List) {
      _invalidCollection(path, report);
      return List<AppearancePreset?>.filled(6, null);
    }
    final result = <AppearancePreset?>[];
    for (var index = 0; index < value.length && index < 6; index++) {
      final presetValue = value[index];
      if (presetValue == null) {
        result.add(null);
        continue;
      }
      if (depth >= 8) {
        report.add(
          path: '$path[$index]',
          code: 'preset-depth-limit',
          message:
              'Nested preset depth exceeded the safety limit and was cleared.',
        );
        result.add(null);
        continue;
      }
      final object = _asObject(presetValue);
      if (object == null) {
        report.add(
          path: '$path[$index]',
          code: 'invalid-preset',
          message:
              'Appearance preset must be an object or null and was cleared.',
        );
        result.add(null);
        continue;
      }
      final reader = _ObjectReader(object, '$path[$index]', report);
      result.add(
        AppearancePreset(
          name: _readFlexibleString(
            reader.take('name'),
            '$path[$index].name',
            report,
            fallback: 'Preset',
          )!,
          settings: _readAppearance(
            reader.take('settings'),
            mode,
            '$path[$index].settings',
            report,
            depth: depth + 1,
          ),
          extensions: reader.extensions(),
        ),
      );
    }
    while (result.length < 6) {
      result.add(null);
    }
    if (value.length > 6) {
      report.add(
        path: path,
        code: 'preset-count',
        message: 'Only the first six appearance presets were retained.',
        severity: MigrationDiagnosticSeverity.notice,
      );
    }
    return result;
  }

  String _normalizeBackground(
    String source,
    String fallback,
    String path,
    MigrationReportBuilder report,
  ) {
    final normalized = source.trim().toLowerCase();
    const retained = {
      'illuminated-ledger',
      'sakura-night-garden',
      'greenhouse',
      'orrery',
      'hearth',
      'frostbound',
      'summer',
      'tide',
      'lagoon',
      'reef',
      'plain-dark',
      'plain-verdant',
      'plain-violet',
      'plain-amber',
      'plain-cobalt',
      'plain-rose',
    };
    if (normalized == 'ledger') return 'illuminated-ledger';
    if (normalized == 'sakura' || normalized == 'sakura-night') {
      return 'sakura-night-garden';
    }
    if (retained.contains(normalized)) return normalized;

    const legacyWaterIds = {'abyssal-tideglass', 'tideglass', 'abyssal'};
    if (legacyWaterIds.contains(normalized)) {
      report.add(
        path: path,
        code: 'excluded-background-mapped',
        message: 'Legacy background "$source" was mapped to "tide".',
        severity: MigrationDiagnosticSeverity.notice,
      );
      return 'tide';
    }

    const legacyAstralIds = {'moonstone-astrarium', 'moonstone', 'astrarium'};
    if (legacyAstralIds.contains(normalized)) {
      report.add(
        path: path,
        code: 'excluded-background-mapped',
        message: 'Legacy background "$source" was mapped to "orrery".',
        severity: MigrationDiagnosticSeverity.notice,
      );
      return 'orrery';
    }

    report.add(
      path: path,
      code: 'unknown-background',
      message: 'Unknown background "$source" was mapped to "$fallback".',
    );
    return fallback;
  }

  Map<String, double> _readProcessingYields(
    Object? value,
    String path,
    MigrationReportBuilder report,
  ) {
    final source = _readNumberMap(
      value,
      path,
      report,
      allowZero: true,
      retainNegativeForNormalization: true,
    );
    const methods = [
      'Shaking',
      'Grinding',
      'Chopping',
      'Drying',
      'Heating',
      'Filtering',
      'Thinning',
      'Simple Alchemy',
      'Simple Cooking',
      'Other',
    ];
    double lookup(String key) {
      for (final entry in source.entries) {
        if (entry.key.toLowerCase() == key.toLowerCase()) return entry.value;
      }
      return 0;
    }

    final defaultYield = lookup('defaultYield');
    return {
      'defaultYield': defaultYield > 0 ? defaultYield : 2.5,
      for (final method in methods)
        method: lookup(method) > 0 ? lookup(method) : 0,
    };
  }

  MarketTax _readMarketTax(
    Object? value,
    String path,
    MigrationReportBuilder report,
  ) {
    final object = value == _absent || value == null ? null : _asObject(value);
    if (object == null) {
      if (value != _absent && value != null) _invalidCollection(path, report);
      return MarketTax();
    }
    final reader = _ObjectReader(object, path, report);
    final result = MarketTax(
      enabled: _readBool(
        reader.take('enabled'),
        '$path.enabled',
        report,
        fallback: true,
      ),
      valuePack: _readBool(
        reader.take('valuePack'),
        '$path.valuePack',
        report,
        fallback: false,
      ),
      merchantRing: _readBool(
        reader.take('merchantRing'),
        '$path.merchantRing',
        report,
        fallback: false,
      ),
      familyFameBonus: _readFiniteDouble(
        reader.take('familyFameBonus'),
        '$path.familyFameBonus',
        report,
        fallback: 0,
      ),
      extensions: reader.extensions(),
    );
    return result;
  }
}

class _ObjectReader {
  _ObjectReader(this.source, this.path, this.report);

  final Map<String, Object?> source;
  final String path;
  final MigrationReportBuilder report;
  final Set<String> _consumed = {};

  Object? take(String canonicalName) {
    final matches = source.keys
        .where((key) => key.toLowerCase() == canonicalName.toLowerCase())
        .toList(growable: false);
    if (matches.isEmpty) return _absent;
    _consumed.addAll(matches);
    final selected = matches.contains(canonicalName)
        ? canonicalName
        : matches.first;
    if (matches.length > 1) {
      report.add(
        path: '$path.$canonicalName',
        code: 'case-insensitive-property-collision',
        message:
            'Multiple property spellings matched "$canonicalName"; "$selected" won.',
      );
    }
    return source[selected];
  }

  Map<String, Object?> extensions() {
    final extensions = <String, Object?>{};
    for (final entry in source.entries) {
      if (_consumed.contains(entry.key)) continue;
      extensions[entry.key] = immutableJsonValue(entry.value);
      report.increment('unknownFields');
      report.add(
        path: '$path.${entry.key}',
        code: 'unknown-field-preserved',
        message: 'Unknown field was preserved in the extension bucket.',
        severity: MigrationDiagnosticSeverity.notice,
      );
    }
    return extensions;
  }
}

Map<String, Object?>? _asObject(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

int _readVersion(Object? value, String path, MigrationReportBuilder report) {
  if (value == _absent || value == null) return 1;
  if (value is int) {
    if (value >= 1) return value;
    report.add(
      path: path,
      code: 'source-version-floor',
      message: 'Nonpositive source version was normalized to 1.',
      severity: MigrationDiagnosticSeverity.notice,
    );
    return 1;
  }
  report.add(
    path: path,
    code: 'invalid-integer',
    message: 'Expected an integer; version 1 was used.',
  );
  return 1;
}

CraftMode _readMode(Object? value, String path, MigrationReportBuilder report) {
  final text = _readFlexibleString(
    value,
    path,
    report,
    fallback: 'alchemy',
  )!.trim().toLowerCase();
  return switch (text) {
    'cooking' => CraftMode.cooking,
    'processing' => CraftMode.processing,
    'alchemy' => CraftMode.alchemy,
    _ => () {
      report.add(
        path: path,
        code: 'unknown-mode',
        message: 'Unknown mode "$text" was normalized to "alchemy".',
      );
      return CraftMode.alchemy;
    }(),
  };
}

String? _readFlexibleString(
  Object? value,
  String path,
  MigrationReportBuilder report, {
  String? fallback,
}) {
  if (value == _absent) return fallback;
  if (value == null) return fallback;
  if (value is String) return value;
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return value.toString();
  if (value is double && value.isFinite) return value.toString();
  report.add(
    path: path,
    code: 'invalid-flexible-string',
    message: 'Expected a string, number, boolean, or null; default was used.',
  );
  return fallback;
}

bool _readBool(
  Object? value,
  String path,
  MigrationReportBuilder report, {
  required bool fallback,
}) {
  if (value == _absent || value == null) return fallback;
  if (value is bool) return value;
  report.add(
    path: path,
    code: 'invalid-boolean',
    message: 'Expected a boolean; default was used.',
  );
  return fallback;
}

double _readFiniteDouble(
  Object? value,
  String path,
  MigrationReportBuilder report, {
  required double fallback,
}) {
  if (value == _absent || value == null) return fallback;
  if (value is num && value.toDouble().isFinite) return value.toDouble();
  report.add(
    path: path,
    code: 'invalid-number',
    message: 'Expected a finite number; default was used.',
  );
  return fallback;
}

double? _readNullableFiniteDouble(
  Object? value,
  String path,
  MigrationReportBuilder report,
) {
  if (value == _absent || value == null) return null;
  if (value is num && value.toDouble().isFinite) return value.toDouble();
  report.add(
    path: path,
    code: 'invalid-number',
    message: 'Expected a finite number or null; null was used.',
  );
  return null;
}

double _readNonNegativeDouble(
  Object? value,
  String path,
  MigrationReportBuilder report,
) {
  final result = _readFiniteDouble(value, path, report, fallback: 0);
  if (result >= 0) return result;
  report.add(
    path: path,
    code: 'negative-number',
    message: 'Negative value was normalized to 0.',
  );
  return 0;
}

int _readIntAtLeast(
  Object? value,
  String path,
  MigrationReportBuilder report, {
  required int fallback,
  required int minimum,
}) {
  if (value == _absent || value == null) {
    return fallback.clamp(minimum, 1 << 62);
  }
  if (value is int) return value < minimum ? minimum : value;
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt() < minimum ? minimum : value.toInt();
  }
  report.add(
    path: path,
    code: 'invalid-integer',
    message: 'Expected an integer; default was used.',
  );
  return fallback.clamp(minimum, 1 << 62);
}

int _readClampedInt(
  Object? value,
  String path,
  MigrationReportBuilder report, {
  required int fallback,
  required int minimum,
  required int maximum,
}) {
  final result = _readIntAtLeast(
    value,
    path,
    report,
    fallback: fallback,
    minimum: minimum,
  );
  return result.clamp(minimum, maximum);
}

double _readUnitDouble(
  Object? value,
  String path,
  MigrationReportBuilder report, {
  required double fallback,
}) => _readFiniteDouble(value, path, report, fallback: fallback).clamp(0, 1);

double _readHue(
  Object? value,
  String path,
  MigrationReportBuilder report, {
  required double fallback,
}) => _readFiniteDouble(value, path, report, fallback: fallback).clamp(0, 360);

String _readView(
  Object? value,
  CraftMode mode,
  String path,
  MigrationReportBuilder report,
) {
  final text = _readFlexibleString(
    value,
    path,
    report,
    fallback: 'plan',
  )!.trim().toLowerCase();
  const valid = {'plan', 'bonus', 'inventory', 'editor', 'data', 'appearance'};
  if (!valid.contains(text) || text == 'recipes' || text == 'market') {
    if (text != 'plan') {
      report.add(
        path: path,
        code: 'unknown-view',
        message: 'View "$text" was normalized to "plan".',
        severity: MigrationDiagnosticSeverity.notice,
      );
    }
    return 'plan';
  }
  if (mode == CraftMode.processing && text == 'bonus') return 'plan';
  return text;
}

Map<String, double> _readNumberMap(
  Object? value,
  String path,
  MigrationReportBuilder report, {
  required bool allowZero,
  bool retainNegativeForNormalization = false,
}) {
  if (value == _absent || value == null) return {};
  final object = _asObject(value);
  if (object == null) {
    _invalidCollection(path, report);
    return {};
  }
  final result = <String, double>{};
  for (final entry in object.entries) {
    if (entry.key.trim().isEmpty) {
      _dropBlankKey(path, report);
      continue;
    }
    final number = entry.value is num ? (entry.value as num).toDouble() : null;
    final valid =
        number != null &&
        number.isFinite &&
        (retainNegativeForNormalization ||
            (allowZero ? number >= 0 : number > 0));
    if (!valid) {
      report.add(
        path: '$path.${entry.key}',
        code: 'invalid-map-number',
        message: 'Invalid numeric map value was dropped.',
      );
      continue;
    }
    result[entry.key] = number;
  }
  return result;
}

Map<String, int> _readNonnegativeIntMap(
  Object? value,
  String path,
  MigrationReportBuilder report,
) {
  if (value == _absent || value == null) return {};
  final object = _asObject(value);
  if (object == null) {
    _invalidCollection(path, report);
    return {};
  }
  final result = <String, int>{};
  for (final entry in object.entries) {
    if (entry.key.trim().isEmpty) {
      _dropBlankKey(path, report);
      continue;
    }
    final number = entry.value;
    if (number is! num ||
        !number.isFinite ||
        number < 0 ||
        number != number.truncate()) {
      report.add(
        path: '$path.${entry.key}',
        code: 'invalid-map-integer',
        message: 'Invalid nonnegative integer map value was dropped.',
      );
      continue;
    }
    result[entry.key] = number.toInt();
  }
  return result;
}

Map<String, String> _readStringMap(
  Object? value,
  String path,
  MigrationReportBuilder report,
) {
  if (value == _absent || value == null) return {};
  final object = _asObject(value);
  if (object == null) {
    _invalidCollection(path, report);
    return {};
  }
  final result = <String, String>{};
  for (final entry in object.entries) {
    if (entry.key.trim().isEmpty) {
      _dropBlankKey(path, report);
      continue;
    }
    final text = _readFlexibleString(entry.value, '$path.${entry.key}', report);
    if (text != null) result[entry.key] = text;
  }
  return result;
}

Map<String, String> _readGrades(
  Object? value,
  String path,
  MigrationReportBuilder report,
) {
  final source = _readStringMap(value, path, report);
  const valid = {'normal', 'high', 'special', 'blue'};
  final result = <String, String>{};
  for (final entry in source.entries) {
    final normalized = entry.value.trim().toLowerCase();
    if (valid.contains(normalized)) {
      result[entry.key] = normalized;
      continue;
    }
    report.add(
      path: '$path.${entry.key}',
      code: 'invalid-grade',
      message: 'Unknown ingredient grade "${entry.value}" was dropped.',
    );
  }
  return result;
}

List<String> _readNormalizedStringList(
  Object? value,
  String path,
  MigrationReportBuilder report,
) {
  if (value == _absent || value == null) return [];
  if (value is! List) {
    _invalidCollection(path, report);
    return [];
  }
  final byFolded = <String, String>{};
  for (var index = 0; index < value.length; index++) {
    final text = _readFlexibleString(
      value[index],
      '$path[$index]',
      report,
    )?.trim();
    if (text == null || text.isEmpty) continue;
    byFolded.putIfAbsent(text.toLowerCase(), () => text);
  }
  final result = byFolded.values.toList();
  result.sort((left, right) {
    final folded = left.toLowerCase().compareTo(right.toLowerCase());
    return folded != 0 ? folded : left.compareTo(right);
  });
  return result;
}

List<String> _readFlexibleStringListPreservingOrder(
  Object? value,
  String path,
  MigrationReportBuilder report,
) {
  if (value == _absent || value == null) return [];
  if (value is! List) {
    _invalidCollection(path, report);
    return [];
  }
  final result = <String>[];
  for (var index = 0; index < value.length; index++) {
    final text = _readFlexibleString(value[index], '$path[$index]', report);
    if (text != null) result.add(text);
  }
  return result;
}

Map<String, Object?> _readRawObject(
  Object? value,
  String path,
  MigrationReportBuilder report,
) {
  if (value == _absent || value == null) return {};
  final object = _asObject(value);
  if (object == null) {
    _invalidCollection(path, report);
    return {};
  }
  return {
    for (final entry in object.entries)
      if (entry.key.trim().isNotEmpty)
        entry.key: immutableJsonValue(entry.value),
  };
}

String _readEnumString(
  Object? value,
  String path,
  MigrationReportBuilder report, {
  required String fallback,
  required Set<String> allowed,
}) {
  final text = _readFlexibleString(
    value,
    path,
    report,
    fallback: fallback,
  )!.trim().toLowerCase();
  if (allowed.contains(text)) return text;
  report.add(
    path: path,
    code: 'invalid-enum',
    message: 'Unknown value "$text" was normalized to "$fallback".',
  );
  return fallback;
}

String _normalizeTabTransition(String? value, bool tabFade) {
  return switch ((value ?? '').trim().toLowerCase()) {
    'off' || 'none' => 'off',
    'fade' => 'fade',
    'lift' || 'rise' => 'lift',
    'slide' || 'fly' || 'fly-in' => 'slide',
    _ => tabFade ? 'slide' : 'off',
  };
}

void _invalidCollection(String path, MigrationReportBuilder report) {
  report.add(
    path: path,
    code: 'invalid-collection',
    message: 'Expected a JSON object or array; an empty default was used.',
  );
}

void _dropBlankKey(String path, MigrationReportBuilder report) {
  report.add(
    path: path,
    code: 'blank-key',
    message: 'A blank map key was dropped.',
  );
}
