import '../../app/state/planner_application_controller.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/state/inventory_storage.dart';
import '../../domain/state/user_source_notes.dart';

final class InventoryItemRecord {
  const InventoryItemRecord({
    required this.name,
    required this.recipe,
    required this.category,
    required this.smartGroup,
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
    final state = controller.state.value;
    final recipes = controller.recipes;
    final bundledItems = controller.owner.catalog
        .forMode(controller.mode)
        .items;
    final aliases = controller.owner.catalog
        .forMode(controller.mode)
        .searchAliases;
    final metadataByName = _foldedValues(state.ingredientMeta);
    final bundledByName = _foldedValues(bundledItems);
    final editsByName = _foldedValues(state.recipeEdits);
    final inventoryByName = _foldedValues(state.inventory);
    final aliasKeywordsByName = _aliasKeywords(aliases);
    final storage = InventoryStorageState.fromModeState(state);
    final names = <String, String>{};
    void addName(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      names.putIfAbsent(_fold(trimmed), () => trimmed);
    }

    for (final name in recipes.keys) {
      addName(name);
    }
    for (final name in state.inventory.keys) {
      addName(name);
    }
    for (final location in storage.locations) {
      for (final name in location.quantities.keys) {
        addName(name);
      }
    }
    final items = <InventoryItemRecord>[];
    for (final name in names.values) {
      final foldedName = _fold(name);
      final recipe = _foldedRecipe(recipes, foldedName);
      final metadata = metadataByName[foldedName];
      final bundledRecipe = bundledByName[foldedName];
      final userOnly = bundledRecipe == null && editsByName[foldedName] != null;
      final category =
          _nonBlank(metadata?.category) ??
          (recipe == null ? 'Saved items' : _category(recipe));
      final bundledCategory = bundledRecipe == null
          ? (recipe == null ? 'Saved items' : _defaultCategory(recipe))
          : _defaultCategory(bundledRecipe);
      final equipmentLike = _isEquipmentLike(name, category, recipe);
      items.add(
        InventoryItemRecord(
          name: name,
          recipe: recipe,
          category: category,
          smartGroup: _smartGroup(name, category, recipe),
          owned: inventoryByName[foldedName] ?? 0,
          sourceNote: displayableUserSourceNote(state, name),
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
    items.sort((left, right) => _compareNames(left.name, right.name));

    final categoryNames = <String>[];
    for (final item in items) {
      _addDistinct(categoryNames, item.category);
    }
    for (final category in state.customCategories) {
      final normalized = normalizeInventoryCategory(category);
      if (normalized.isNotEmpty) _addDistinct(categoryNames, normalized);
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

String _smartGroup(String name, String category, Recipe? recipe) {
  final foldedName = _fold(name);
  final text = _fold(
    '$name $category ${recipe?.group ?? ''} ${recipe?.type ?? ''}',
  );
  if (_craftedBloods.contains(foldedName)) return 'Crafted bloods';
  if (RegExp(r'\bblood\b').hasMatch(text)) return 'Bloods';
  if (RegExp(r'\b(meat|chicken|poultry)\b').hasMatch(text)) return 'Meats';
  if (RegExp(r'\b(mushroom|truffle)\b').hasMatch(text)) return 'Mushrooms';
  if (RegExp(r'\b(log|timber|plank|plywood|sap|wood)\b').hasMatch(text)) {
    return 'Lumber & sap';
  }
  if (RegExp(r'\b(ore|ingot|melted|metal|coal)\b').hasMatch(text)) {
    return 'Ore & metal';
  }
  if (RegExp(
    r'\b(herb|flower|fruit|vegetable|grain|seed|wheat|barley|corn|potato|onion|pepper|garlic|strawberry)\b',
  ).hasMatch(text)) {
    return 'Plants & crops';
  }
  if (RegExp(
    r'\b(salt|sugar|leavening|sauce|oil|water|milk|cream|cheese|egg|flour|dough|cooking)\b',
  ).hasMatch(text)) {
    return 'Cooking materials';
  }
  if (RegExp(
    r'\b(reagent|solvent|trace|powder|alchemy|essence|sap)\b',
  ).hasMatch(text)) {
    return 'Alchemy materials';
  }
  if (recipe?.hasRecordedRecipe ?? false) return 'Processed materials';
  return 'Miscellaneous';
}

bool _isEquipmentLike(String name, String category, Recipe? recipe) {
  final text = _fold(
    '$name $category ${recipe?.group ?? ''} ${recipe?.type ?? ''}',
  );
  return RegExp(
    r'\b(accessor(y|ies)|crystal|lightstone|artifact|weapon|armor|earring|ring|belt|necklace|helmet|gloves|shoes)\b',
  ).hasMatch(text);
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
