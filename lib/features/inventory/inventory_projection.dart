import '../../app/state/planner_application_controller.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/user_source_notes.dart';

final class InventoryItemRecord {
  const InventoryItemRecord({
    required this.name,
    required this.recipe,
    required this.category,
    required this.smartGroup,
    required this.section,
    required this.subsection,
    required this.sectionOrder,
    required this.subsectionOrder,
    required this.owned,
    required this.sourceNote,
    required this.vendor,
    required this.location,
    required this.searchKeywords,
    required this.bundled,
    required this.bundledCategory,
    required this.savedOnly,
    required this.equipmentLike,
  });

  final String name;
  final Recipe? recipe;
  final String category;
  final String smartGroup;
  final String section;
  final String subsection;
  final int sectionOrder;
  final int subsectionOrder;
  final double owned;
  final String? sourceNote;
  final String? vendor;
  final String? location;
  final String? searchKeywords;
  final bool bundled;
  final String bundledCategory;
  final bool savedOnly;
  final bool equipmentLike;

  bool matches(String query) {
    final normalized = _fold(query);
    if (normalized.isEmpty) return true;
    return <String?>[
      name,
      category,
      section,
      subsection,
      sourceNote,
      vendor,
      location,
      searchKeywords,
    ].whereType<String>().any((value) => _fold(value).contains(normalized));
  }
}

final class InventoryGroupRecord {
  const InventoryGroupRecord({required this.name, required this.itemCount});

  final String name;
  final int itemCount;
}

final class InventoryProjection {
  const InventoryProjection({required this.items, required this.groups});

  factory InventoryProjection.assemble(ModeFeatureController controller) {
    final owner = controller.owner;
    final orderedModes = <CraftMode>[
      controller.mode,
      for (final mode in CraftMode.values)
        if (mode != controller.mode) mode,
    ];
    final modeControllers = <ModeFeatureController>[
      for (final mode in orderedModes) owner.modes[mode]!,
    ];
    final states = <ModeState>[
      for (final modeController in modeControllers) modeController.state.value,
    ];
    final recipes = <String, Recipe>{};
    final bundledItems = <String, Recipe>{};
    final taxonomyRecipesByName = <String, List<Recipe>>{};
    final usedByModesByName = <String, Set<CraftMode>>{};
    final cookingProductNames = <String>{};
    final cookingCatalogNames = <String>{};
    final driedFishNames = <String>{};
    final alchemyMaterialNames = <String>{};
    final processingSimpleCookingNames = <String>{};
    final processingSimpleAlchemyNames = <String>{};
    final processingProductNames = <String>{};
    final metadataByName = <String, IngredientMetadata>{};
    final editedNames = <String>{};
    final aliasKeywordsByName = <String, List<String>>{};

    void addRecipe(Map<String, Recipe> target, String name, Recipe recipe) {
      if (!target.keys.any((existing) => _same(existing, name))) {
        target[name] = recipe;
      }
    }

    void recordTaxonomyRecipe(String name, Recipe recipe, CraftMode mode) {
      final foldedName = _fold(name);
      taxonomyRecipesByName
          .putIfAbsent(foldedName, () => <Recipe>[])
          .add(recipe);
      final group = _fold(recipe.group ?? '');
      final method = _fold(recipe.method ?? '');
      if (mode == CraftMode.cooking) cookingCatalogNames.add(foldedName);
      if (mode == CraftMode.cooking && group == 'dried fish') {
        driedFishNames.add(foldedName);
      }
      if (mode == CraftMode.cooking &&
          (group == 'cooking' ||
              (_fold(recipe.type) == 'cooking' && recipe.hasRecordedRecipe))) {
        cookingProductNames.add(foldedName);
      }
      if (mode == CraftMode.alchemy && group == 'alchemy materials') {
        alchemyMaterialNames.add(foldedName);
      }
      if (mode == CraftMode.processing &&
          (group == 'processing - simple cooking' ||
              method == 'simple cooking')) {
        processingSimpleCookingNames.add(foldedName);
      }
      if (mode == CraftMode.processing &&
          (group == 'processing - simple alchemy' ||
              method == 'simple alchemy')) {
        processingSimpleAlchemyNames.add(foldedName);
      }
      if (mode == CraftMode.processing && recipe.hasRecordedRecipe) {
        processingProductNames.add(foldedName);
      }
      final formulas = <Iterable<Ingredient>>[
        recipe.ingredients,
        for (final variant in recipe.variants) variant.ingredients,
      ];
      final seenIngredients = <String>{};
      for (final ingredient in formulas.expand((value) => value)) {
        final driedFishGroup =
            mode == CraftMode.cooking &&
            _fold(ingredient.substituteGroup ?? '') == 'bdo group 6';
        for (final ingredientName in <String>[
          ingredient.name,
          ...ingredient.options,
        ]) {
          final foldedIngredient = _fold(ingredientName);
          if (foldedIngredient.isEmpty ||
              !seenIngredients.add(foldedIngredient)) {
            continue;
          }
          if (driedFishGroup) driedFishNames.add(foldedIngredient);
          usedByModesByName
              .putIfAbsent(foldedIngredient, () => <CraftMode>{})
              .add(mode);
        }
      }
    }

    for (var index = 0; index < orderedModes.length; index += 1) {
      final mode = orderedModes[index];
      final state = states[index];
      for (final entry in modeControllers[index].recipes.entries) {
        recordTaxonomyRecipe(entry.key, entry.value, mode);
        addRecipe(recipes, entry.key, entry.value);
      }
      for (final entry in owner.catalog.forMode(mode).items.entries) {
        addRecipe(bundledItems, entry.key, entry.value);
      }
      for (final entry in state.ingredientMeta.entries) {
        metadataByName.putIfAbsent(_fold(entry.key), () => entry.value);
      }
      for (final entry in state.recipeEdits.entries) {
        editedNames.add(_fold(entry.key));
      }
      final aliases = _aliasKeywords(owner.catalog.forMode(mode).searchAliases);
      for (final entry in aliases.entries) {
        final target = aliasKeywordsByName.putIfAbsent(
          entry.key,
          () => <String>[],
        );
        for (final value in entry.value) {
          if (!target.any((existing) => _same(existing, value))) {
            target.add(value);
          }
        }
      }
    }
    final bundledByName = _foldedValues(bundledItems);
    final inventoryByName = _foldedValues(
      owner.documentSnapshot.alchemy.inventory,
    );
    final bloodFamilies = _bloodFamilies(
      owner.catalog.alchemy.metadata['bloodGroups'],
    );
    final meatFamilies = _meatFamilies(recipes);
    final catalogItemIdsByName = _catalogItemIds(owner.catalog.supportingData);
    final names = <String, String>{};
    void addName(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      names.putIfAbsent(_fold(trimmed), () => trimmed);
    }

    for (final name in recipes.keys) {
      addName(name);
    }
    for (final state in states) {
      for (final name in state.inventory.keys) {
        addName(name);
      }
    }
    final items = <InventoryItemRecord>[];
    for (final name in names.values) {
      final foldedName = _fold(name);
      final recipe = _foldedRecipe(recipes, foldedName);
      final metadata = metadataByName[foldedName];
      final bundledRecipe = bundledByName[foldedName];
      final userOnly =
          bundledRecipe == null && editedNames.contains(foldedName);
      final category =
          _nonBlank(metadata?.category) ??
          (recipe == null ? 'Saved items' : _category(recipe));
      final bundledCategory = bundledRecipe == null
          ? (recipe == null ? 'Saved items' : _defaultCategory(recipe))
          : _defaultCategory(bundledRecipe);
      final recipeCandidates =
          taxonomyRecipesByName[foldedName] ??
          (recipe == null ? const <Recipe>[] : <Recipe>[recipe]);
      final usedByModes = usedByModesByName[foldedName] ?? const <CraftMode>{};
      final equipmentLike = _isEquipmentLike(category, recipeCandidates);
      String? sourceNote;
      for (final state in states) {
        sourceNote ??= displayableUserSourceNote(state, name);
      }
      final home = _inventoryHome(
        name: name,
        category: category,
        savedOnly: recipe == null,
        bloodFamilies: bloodFamilies,
        meatFamilies: meatFamilies,
        recipeCandidates: recipeCandidates,
        itemIds: <String>{
          for (final candidate in recipeCandidates)
            ?_nonBlank(candidate.marketId),
          ?catalogItemIdsByName[foldedName],
        },
        usedByModes: usedByModes,
        cookingProduct: cookingProductNames.contains(foldedName),
        cookingCatalogItem: cookingCatalogNames.contains(foldedName),
        driedFish: driedFishNames.contains(foldedName),
        explicitAlchemyMaterial: alchemyMaterialNames.contains(foldedName),
        processingSimpleCooking: processingSimpleCookingNames.contains(
          foldedName,
        ),
        processingSimpleAlchemy: processingSimpleAlchemyNames.contains(
          foldedName,
        ),
        processingProduct: processingProductNames.contains(foldedName),
      );
      items.add(
        InventoryItemRecord(
          name: name,
          recipe: recipe,
          category: category,
          smartGroup: home.subsection,
          section: home.section,
          subsection: home.subsection,
          sectionOrder: home.sectionOrder,
          subsectionOrder: home.subsectionOrder,
          owned: inventoryByName[foldedName] ?? 0,
          sourceNote: sourceNote,
          vendor: _firstNonBlank(metadata?.vendor, recipe?.vendor),
          location: _firstNonBlank(metadata?.location, recipe?.location),
          searchKeywords: _joinedKeywords(
            metadata?.searchKeywords,
            aliasKeywordsByName[foldedName],
          ),
          bundled: !userOnly,
          bundledCategory: bundledCategory,
          savedOnly: recipe == null,
          equipmentLike: equipmentLike,
        ),
      );
    }
    items.sort((left, right) {
      final section = left.sectionOrder.compareTo(right.sectionOrder);
      if (section != 0) return section;
      final subsection = left.subsectionOrder.compareTo(right.subsectionOrder);
      if (subsection != 0) return subsection;
      return _compareNames(left.name, right.name);
    });

    final categoryNames = <String>[];
    for (final item in items) {
      _addDistinct(categoryNames, item.category);
    }
    for (final state in states) {
      for (final category in state.customCategories) {
        final normalized = normalizeInventoryCategory(category);
        if (normalized.isNotEmpty) _addDistinct(categoryNames, normalized);
      }
    }
    if (categoryNames.isEmpty) categoryNames.add('Base Items');
    categoryNames.sort(_compareNames);
    final itemCounts = <String, int>{};
    for (final item in items) {
      final key = _fold(item.category);
      itemCounts[key] = (itemCounts[key] ?? 0) + 1;
    }
    final groups = <InventoryGroupRecord>[
      for (final category in categoryNames)
        InventoryGroupRecord(
          name: category,
          itemCount: itemCounts[_fold(category)] ?? 0,
        ),
    ];
    return InventoryProjection(
      items: List<InventoryItemRecord>.unmodifiable(items),
      groups: List<InventoryGroupRecord>.unmodifiable(groups),
    );
  }

  final List<InventoryItemRecord> items;
  final List<InventoryGroupRecord> groups;

  String repairCategory(String requested) {
    for (final group in groups) {
      if (_same(group.name, requested)) return group.name;
    }
    return groups.first.name;
  }

  List<InventoryItemRecord> visibleItems({
    required String category,
    required String search,
  }) => items
      .where((item) => _same(item.category, category) && item.matches(search))
      .toList(growable: false);
}

Recipe? _foldedRecipe(Map<String, Recipe> recipes, String foldedName) {
  for (final entry in recipes.entries) {
    if (_fold(entry.key) == foldedName) return entry.value;
  }
  return null;
}

const _craftedBloods = <String>{
  "clown's blood",
  "sinner's blood",
  "wise man's blood",
  "tyrant's blood",
  "legendary beast's blood",
};

// These are reviewed, genuinely plantable or farming-conversion seeds. Do not
// infer farming merely from the word "seed": Seed of Void is an Elvia drop.
const _reviewedFarmingMaterials = <String>{
  'mysterious seed',
  'magical napa cabbage seed',
  'magical perilla seed',
  'magical radish seed',
  'magical rice seed',
  'special napa cabbage seed',
  'special perilla seed',
  'special radish seed',
  'special rice seed',
};

final class _InventoryHome {
  const _InventoryHome(
    this.section,
    this.subsection,
    this.sectionOrder,
    this.subsectionOrder,
  );

  final String section;
  final String subsection;
  final int sectionOrder;
  final int subsectionOrder;
}

// Reviewed identities backed by the canonical BDO item ID and the item's
// recorded description/acquisition or recipe role. These deliberately win
// over broad legacy groups such as "Alchemy Materials" and over words in the
// display name. Unknown identities fall through to structured catalog facts
// and ultimately Miscellaneous.
const _reviewedInventoryHomesById = <String, _InventoryHome>{
  // Cooking intermediates and seasonings.
  '9003': _InventoryHome('Cooking', 'Cooking basics', 4, 4), // White Sauce
  '9004': _InventoryHome('Cooking', 'Cooking basics', 4, 4), // Red Sauce
  '9006': _InventoryHome('Cooking', 'Cooking basics', 4, 4), // Dressing
  '9057': _InventoryHome('Cooking', 'Cooking basics', 4, 4),
  '9066': _InventoryHome('Cooking', 'Cooking basics', 4, 4), // Vinegar
  '9077': _InventoryHome('Cooking', 'Cooking basics', 4, 4),

  // Raw and processed mineral/wood identities.
  '4006': _InventoryHome('Ores & minerals', 'Ore & raw minerals', 3, 0),
  '4051': _InventoryHome('Ores & minerals', 'Metals', 3, 1),
  '4070': _InventoryHome('Ores & minerals', 'Processed minerals', 3, 3),
  '4097': _InventoryHome('Ores & minerals', 'Processed minerals', 3, 3),
  '4496': _InventoryHome('Ores & minerals', 'Processed minerals', 3, 3),
  '5007': _InventoryHome('Trees & wood', 'Branches & bark', 1, 3),

  // Specific Alchemy ingredients whose names resemble another material.
  '4925': _InventoryHome('Alchemy materials', 'Special ingredients', 5, 3),
  '5602': _InventoryHome('Alchemy materials', 'Special ingredients', 5, 3),
  '5605': _InventoryHome('Alchemy materials', 'Traces & powders', 5, 2),
  '8133': _InventoryHome('Alchemy materials', 'Special ingredients', 5, 3),

  // Enhancement, reform, horse, and general crafting products. They are
  // valid Inventory entries but not ore merely because their name says Stone.
  '4901': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '4999': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '50801': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '16001': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '16004': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '44304': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '44305': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '44306': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '45338': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '721003': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '752021': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '752022': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '757003': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '820934': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '821249': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '4910': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '4911': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '4912': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
  '4913': _InventoryHome('Miscellaneous', 'Processed & other', 8, 0),
};

const _reviewedInventoryHomesByName = <String, _InventoryHome>{
  // These legacy records do not currently carry their canonical ID into the
  // assembled planner recipe, so the reviewed exact canonical name is used.
  'rough marble': _InventoryHome('Ores & minerals', 'Ore & raw minerals', 3, 0),
  'polished marble': _InventoryHome(
    'Ores & minerals',
    'Processed minerals',
    3,
    3,
  ),
  'flower of oblivion': _InventoryHome(
    'Miscellaneous',
    'Processed & other',
    8,
    0,
  ),
  'tears of the falling moon': _InventoryHome(
    'Alchemy materials',
    'Special ingredients',
    5,
    3,
  ),
  'concentrated magical black stone (armor)': _InventoryHome(
    'Miscellaneous',
    'Processed & other',
    8,
    0,
  ),
};

_InventoryHome? _reviewedInventoryHome({
  required String foldedName,
  required Set<String> itemIds,
}) {
  for (final itemId in itemIds) {
    final normalized = itemId.trim();
    final exact = _reviewedInventoryHomesById[normalized];
    if (exact != null) return exact;
    final numeric = int.tryParse(normalized);
    if (numeric != null && numeric >= 8801 && numeric <= 8865) {
      return const _InventoryHome('Miscellaneous', 'Processed & other', 8, 0);
    }
  }
  return _reviewedInventoryHomesByName[foldedName];
}

const _redMeat = <String>{
  'bear meat',
  'beef',
  'deer meat',
  'fox meat',
  'goat meat',
  'lamb meat',
  'pork',
  'raccoon meat',
  'rhino meat',
  'weasel meat',
  'wolf meat',
};
const _birdMeat = <String>{
  'bird meat',
  'chicken meat',
  'flamingo meat',
  'kuku bird meat',
};
const _reptileMeat = <String>{
  'cheetah dragon meat',
  'lizard meat',
  'waragon meat',
  'worm meat',
};

Map<String, String> _bloodFamilies(Object? raw) {
  final result = <String, String>{};
  if (raw is! Map) return result;
  for (final entry in raw.entries) {
    final key = entry.key.toString().trim();
    final number = RegExp(r'\d+').firstMatch(key)?.group(0);
    final label = number == null ? key : 'Blood Group $number';
    final members = entry.value;
    if (members is! Iterable) continue;
    for (final member in members) {
      if (member is String && member.trim().isNotEmpty) {
        result[_fold(member)] = label;
      }
    }
  }
  return result;
}

Map<String, String> _catalogItemIds(Map<String, Object?> supportingData) {
  final result = <String, String>{};

  void add(String name, Object? rawId) {
    final normalizedName = _fold(name);
    final id = switch (rawId) {
      final int value => '$value',
      final num value when value.isFinite => '${value.toInt()}',
      final String value => value.trim(),
      _ => '',
    };
    if (normalizedName.isNotEmpty && id.isNotEmpty) {
      result.putIfAbsent(normalizedName, () => id);
    }
  }

  final acquisition = supportingData['acquisitionInfo'];
  if (acquisition is Map) {
    for (final entry in acquisition.entries) {
      final details = entry.value;
      if (details is! Map) continue;
      add(entry.key.toString(), details['itemId']);
      final canonicalName = details['canonicalName'];
      if (canonicalName is String) add(canonicalName, details['itemId']);
    }
  }
  for (final key in const <String>['marketNameIds', 'itemWeightIds']) {
    final names = supportingData[key];
    if (names is! Map) continue;
    for (final entry in names.entries) {
      add(entry.key.toString(), entry.value);
    }
  }
  return result;
}

Map<String, String> _meatFamilies(Map<String, Recipe> recipes) {
  final result = <String, String>{
    for (final name in _redMeat) name: 'Red meat',
    for (final name in _birdMeat) name: 'Bird meat',
    for (final name in _reptileMeat) name: 'Reptile meat',
  };

  void inspect(Ingredient ingredient) {
    final names = <String>[ingredient.name, ...ingredient.options]
        .map(_fold)
        .where((name) => RegExp(r'\b(meat|beef|pork)\b').hasMatch(name))
        .toSet();
    if (names.length < 2) return;
    final group = _fold(ingredient.substituteGroup ?? '');
    final label = group.contains('bird') || names.any(_birdMeat.contains)
        ? 'Bird meat'
        : group.contains('reptile') || names.any(_reptileMeat.contains)
        ? 'Reptile meat'
        : group.contains('red meat') || names.any(_redMeat.contains)
        ? 'Red meat'
        : null;
    if (label != null) {
      for (final name in names) {
        result[name] = label;
      }
    }
  }

  for (final recipe in recipes.values) {
    for (final ingredient in recipe.ingredients) {
      inspect(ingredient);
    }
    for (final variant in recipe.variants) {
      for (final ingredient in variant.ingredients) {
        inspect(ingredient);
      }
    }
  }
  return result;
}

_InventoryHome _inventoryHome({
  required String name,
  required String category,
  required bool savedOnly,
  required Map<String, String> bloodFamilies,
  required Map<String, String> meatFamilies,
  required List<Recipe> recipeCandidates,
  required Set<String> itemIds,
  required Set<CraftMode> usedByModes,
  required bool cookingProduct,
  required bool cookingCatalogItem,
  required bool driedFish,
  required bool explicitAlchemyMaterial,
  required bool processingSimpleCooking,
  required bool processingSimpleAlchemy,
  required bool processingProduct,
}) {
  final foldedName = _fold(name);
  final groups = <String>{
    _fold(category),
    for (final candidate in recipeCandidates) _fold(candidate.group ?? ''),
  }..remove('');
  final bloodFamily = bloodFamilies[foldedName];
  final reviewedHome = _reviewedInventoryHome(
    foldedName: foldedName,
    itemIds: itemIds,
  );
  if (reviewedHome != null) return reviewedHome;
  if (bloodFamily != null) {
    final order = int.tryParse(
      RegExp(r'\d+').firstMatch(bloodFamily)?.group(0) ?? '',
    );
    return _InventoryHome('Animal materials', bloodFamily, 0, order ?? 8);
  }
  if (_craftedBloods.contains(foldedName)) {
    return const _InventoryHome('Animal materials', 'Crafted bloods', 0, 6);
  }
  if (meatFamilies[foldedName] case final family?) {
    final order = switch (family) {
      'Red meat' => 10,
      'Bird meat' => 11,
      'Reptile meat' => 12,
      _ => 13,
    };
    return _InventoryHome('Animal materials', family, 0, order);
  }

  // A product can have several catalog entries. For example, an elixir can
  // also have a Processing > Simple Alchemy upgrade recipe. Combine every
  // mode's facts before considering words such as "steel" or "leather" in
  // its name so the selected craft mode cannot change the item's identity.
  if (groups.contains('elixirs') ||
      RegExp(r'\belixir\b').hasMatch(foldedName)) {
    return const _InventoryHome('Elixirs & buffs', 'Elixirs', 6, 0);
  }
  if (groups.contains('draughts') ||
      RegExp(r'\bdraught\b').hasMatch(foldedName)) {
    return const _InventoryHome('Elixirs & buffs', 'Draughts', 6, 1);
  }
  if (groups.contains('perfumes') ||
      RegExp(r'\bperfume\b').hasMatch(foldedName)) {
    return const _InventoryHome('Elixirs & buffs', 'Perfumes', 6, 2);
  }
  if (RegExp(r'\bpotion\b').hasMatch(foldedName) &&
      recipeCandidates.any(_isAlchemyRelatedRecipe)) {
    return const _InventoryHome('Elixirs & buffs', 'Potions', 6, 3);
  }

  if (cookingProduct) {
    return const _InventoryHome('Cooking', 'Prepared food', 4, 5);
  }

  if (explicitAlchemyMaterial) {
    if (RegExp(
      r'\b(reagent|solvent|glaze|hardener|polisher)\b',
    ).hasMatch(foldedName)) {
      return const _InventoryHome(
        'Alchemy materials',
        'Reagents & crafting additives',
        5,
        0,
      );
    }
    if (RegExp(r'\b(oil|essence)\b').hasMatch(foldedName)) {
      return const _InventoryHome('Alchemy materials', 'Oils & essences', 5, 1);
    }
    if (RegExp(r'\b(trace|powder)\b').hasMatch(foldedName)) {
      return const _InventoryHome(
        'Alchemy materials',
        'Traces & powders',
        5,
        2,
      );
    }
    return const _InventoryHome(
      'Alchemy materials',
      'Special ingredients',
      5,
      3,
    );
  }

  final isAlchemyProduct = recipeCandidates.any(
    (candidate) => _fold(candidate.type) == 'alchemy',
  );
  if (isAlchemyProduct) {
    if (groups.contains('reagents') ||
        RegExp(
          r'\b(reagent|solvent|glaze|hardener|polisher)\b',
        ).hasMatch(foldedName)) {
      return const _InventoryHome(
        'Alchemy materials',
        'Reagents & crafting additives',
        5,
        0,
      );
    }
    if (groups.contains('oils') ||
        RegExp(r'\b(oil|essence)\b').hasMatch(foldedName)) {
      return const _InventoryHome('Alchemy materials', 'Oils & essences', 5, 1);
    }
    if (RegExp(r'\b(trace|powder)\b').hasMatch(foldedName)) {
      return const _InventoryHome(
        'Alchemy materials',
        'Traces & powders',
        5,
        2,
      );
    }
    return const _InventoryHome(
      'Alchemy materials',
      'Other alchemy materials',
      5,
      4,
    );
  }

  if (_isWaterMaterial(foldedName)) {
    return const _InventoryHome('Cooking', 'Water & liquids', 4, 3);
  }
  if (driedFish) {
    return const _InventoryHome('Cooking', 'Fish & seafood', 4, 0);
  }
  if (cookingCatalogItem && RegExp(r'\boil\b').hasMatch(foldedName)) {
    return const _InventoryHome('Cooking', 'Cooking basics', 4, 4);
  }

  // These identities are stronger than method names. In particular,
  // Processing > Simple Alchemy does not turn Black Gems or Bronze Ingots
  // into Alchemy materials, and Blood Ruby is a gemstone rather than blood.
  if (RegExp(r'\b(ore|mineral|coal|stone)\b').hasMatch(foldedName)) {
    return processingProduct
        ? const _InventoryHome('Ores & minerals', 'Processed minerals', 3, 3)
        : const _InventoryHome('Ores & minerals', 'Ore & raw minerals', 3, 0);
  }
  if (RegExp(
    r'\b(ingot|melted|metal|steel|bronze|brass)\b',
  ).hasMatch(foldedName)) {
    return const _InventoryHome('Ores & minerals', 'Metals', 3, 1);
  }
  if (RegExp(
    r'\b(gem|crystal|diamond|ruby|sapphire|emerald|topaz|lightstone)\b',
  ).hasMatch(foldedName)) {
    return const _InventoryHome('Ores & minerals', 'Gems & crystals', 3, 2);
  }

  if (processingSimpleCooking && !foldedName.startsWith('spirit essence of ')) {
    return const _InventoryHome('Cooking', 'Prepared food', 4, 5);
  }
  if (RegExp(r'\b(hide|leather|fur|feather|wool)\b').hasMatch(foldedName)) {
    return const _InventoryHome(
      'Animal materials',
      'Other animal materials',
      0,
      20,
    );
  }
  if (processingSimpleAlchemy) {
    return const _InventoryHome('Miscellaneous', 'Processed & other', 8, 0);
  }

  // Prefer an obvious, human material identity before considering which
  // recipes happen to consume it. A mushroom does not become a vague Alchemy
  // material merely because its current uses are all Alchemy recipes.
  if (RegExp(
    r'\b(sap|log|timber|plank|plywood|wood|branch|tree knot|bark)\b',
  ).hasMatch(foldedName)) {
    if (RegExp(r'\bsap\b').hasMatch(foldedName)) {
      return const _InventoryHome('Trees & wood', 'Sap', 1, 0);
    }
    if (RegExp(r'\b(log|timber)\b').hasMatch(foldedName)) {
      return const _InventoryHome('Trees & wood', 'Logs & timber', 1, 1);
    }
    if (RegExp(r'\b(plank|plywood)\b').hasMatch(foldedName)) {
      return const _InventoryHome('Trees & wood', 'Planks & plywood', 1, 2);
    }
    return const _InventoryHome('Trees & wood', 'Branches & bark', 1, 3);
  }

  if (groups.contains('mushrooms') ||
      RegExp(r'\b(mushroom|truffle)\b').hasMatch(foldedName)) {
    return const _InventoryHome('Plants & farming', 'Mushrooms', 2, 3);
  }
  if (groups.contains('fruit') ||
      (!foldedName.startsWith('fruit of ') &&
          RegExp(
            r'\b(fruit|apple|banana|cherry|grape|pear|pineapple|strawberry)\b',
          ).hasMatch(foldedName))) {
    return const _InventoryHome('Plants & farming', 'Fruit', 2, 2);
  }
  if (groups.contains('herbs') ||
      groups.contains('flowers') ||
      groups.contains('wild herbs') ||
      RegExp(
        r'\b(herb|flower|azalea|tulip|delotia|weed)\b',
      ).hasMatch(foldedName)) {
    return const _InventoryHome('Plants & farming', 'Herbs & flowers', 2, 1);
  }
  if (groups.contains('vegetables') ||
      groups.contains('crops') ||
      groups.contains('grain') ||
      _reviewedFarmingMaterials.contains(foldedName) ||
      RegExp(
        r'\b(crop|vegetable|grain|wheat|barley|corn|potato|onion|pepper|garlic|sunflower|cabbage|pumpkin|olive)\b',
      ).hasMatch(foldedName)) {
    return const _InventoryHome('Plants & farming', 'Crops & vegetables', 2, 0);
  }

  if (groups.contains('seafood') ||
      RegExp(
        r'\b(fish|seafood|shellfish|octopus|squid|shrimp|crab)\b',
      ).hasMatch(foldedName)) {
    return const _InventoryHome('Cooking', 'Fish & seafood', 4, 0);
  }
  if (RegExp(r'\b(milk|cream|cheese|egg|butter)\b').hasMatch(foldedName)) {
    return const _InventoryHome('Cooking', 'Dairy & eggs', 4, 1);
  }
  if (RegExp(r'\b(flour|dough)\b').hasMatch(foldedName)) {
    return const _InventoryHome('Cooking', 'Flour & dough', 4, 2);
  }
  if (groups.contains('cooking materials') ||
      groups.contains('npc items') ||
      RegExp(
        r'\b(salt|sugar|pepper|sauce|leavening agent|vinegar|cooking wine|mineral water)\b',
      ).hasMatch(foldedName)) {
    return const _InventoryHome('Cooking', 'Cooking basics', 4, 4);
  }

  if (RegExp(r'\bblood\b').hasMatch(foldedName)) {
    return const _InventoryHome('Animal materials', 'Other blood', 0, 7);
  }
  if (RegExp(
    r'\b(meat|beef|pork|hide|leather|feather|wool)\b',
  ).hasMatch(foldedName)) {
    return const _InventoryHome(
      'Animal materials',
      'Other animal materials',
      0,
      20,
    );
  }

  // Only actual Alchemy recipes count here. Processing happens to have a
  // method named Simple Alchemy, but that is a different catalog source and
  // must not decide an item's Inventory home.
  final onlyUsedForAlchemy =
      usedByModes.isNotEmpty &&
      usedByModes.every((mode) => mode == CraftMode.alchemy);
  if (onlyUsedForAlchemy) {
    if (RegExp(
      r'\b(reagent|solvent|glaze|hardener|polisher)\b',
    ).hasMatch(foldedName)) {
      return const _InventoryHome(
        'Alchemy materials',
        'Reagents & crafting additives',
        5,
        0,
      );
    }
    if (RegExp(r'\b(oil|essence)\b').hasMatch(foldedName)) {
      return const _InventoryHome('Alchemy materials', 'Oils & essences', 5, 1);
    }
    if (RegExp(r'\b(trace|powder)\b').hasMatch(foldedName)) {
      return const _InventoryHome(
        'Alchemy materials',
        'Traces & powders',
        5,
        2,
      );
    }
    return const _InventoryHome(
      'Alchemy materials',
      'Special ingredients',
      5,
      3,
    );
  }

  if (recipeCandidates.any((candidate) => candidate.hasRecordedRecipe)) {
    return const _InventoryHome('Miscellaneous', 'Processed & other', 8, 0);
  }
  if (savedOnly) {
    return const _InventoryHome('Miscellaneous', 'Saved items', 8, 1);
  }
  return const _InventoryHome('Miscellaneous', 'Other items', 8, 2);
}

bool _isWaterMaterial(String foldedName) {
  if (foldedName.startsWith('spirit essence of ')) return false;
  return foldedName == 'bag of muddy water' ||
      foldedName == 'bottle of clean water' ||
      foldedName == 'bottle of river water' ||
      foldedName == 'bottle of turbid water' ||
      foldedName == 'distilled water' ||
      foldedName == 'mineral water' ||
      foldedName == 'purified water' ||
      foldedName == 'spring water' ||
      (foldedName.startsWith('oquilla ') && foldedName.endsWith(' water'));
}

bool _isAlchemyRelatedRecipe(Recipe recipe) {
  final type = _fold(recipe.type);
  final group = _fold(recipe.group ?? '');
  final method = _fold(recipe.method ?? '');
  return type == 'alchemy' ||
      type == 'simple_alchemy' ||
      method == 'simple alchemy' ||
      RegExp(
        r'\b(alchemy|elixir|draught|perfume|reagent|blood|oil)\b',
      ).hasMatch(group);
}

bool _isEquipmentLike(String category, List<Recipe> recipeCandidates) {
  const explicitEquipmentGroups = <String>{
    'gear crystal',
    'reference - accessory reform',
    'reference - ekleta accessories',
    'reference - godslayer',
  };
  final groups = <String>{
    _fold(category),
    for (final recipe in recipeCandidates) _fold(recipe.group ?? ''),
  }..remove('');
  if (groups.isEmpty ||
      groups.any((group) => !explicitEquipmentGroups.contains(group))) {
    return false;
  }
  return true;
}

String normalizeInventoryCategory(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .join(' ');

String _category(Recipe recipe) =>
    _nonBlank(recipe.group) ??
    (recipe.hasRecordedRecipe ? 'Crafted' : 'Base Items');

String _defaultCategory(Recipe recipe) => _category(recipe);

Map<String, T> _foldedValues<T>(Map<String, T> source) => <String, T>{
  for (final entry in source.entries) _fold(entry.key): entry.value,
};

Map<String, List<String>> _aliasKeywords(Map<String, String> aliases) {
  final result = <String, List<String>>{};
  void add(String name, String keyword) {
    result.putIfAbsent(_fold(name), () => <String>[]).add(keyword);
  }

  for (final entry in aliases.entries) {
    add(entry.key, entry.value);
    add(entry.value, entry.key);
  }
  return result;
}

String? _joinedKeywords(String? explicit, List<String>? aliases) {
  final values = <String>[];
  if (_nonBlank(explicit) case final value?) values.add(value);
  if (aliases != null) values.addAll(aliases);
  return values.isEmpty ? null : values.join(' ');
}

String? _firstNonBlank(String? first, String? second) =>
    _nonBlank(first) ?? _nonBlank(second);

String? _nonBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

void _addDistinct(List<String> target, String value) {
  final normalized = normalizeInventoryCategory(value);
  if (normalized.isEmpty || target.any((item) => _same(item, normalized))) {
    return;
  }
  target.add(normalized);
}

bool _same(String left, String right) => _fold(left) == _fold(right);
String _fold(String value) => value.trim().toLowerCase();
int _compareNames(String left, String right) {
  final folded = _fold(left).compareTo(_fold(right));
  return folded != 0 ? folded : left.compareTo(right);
}
