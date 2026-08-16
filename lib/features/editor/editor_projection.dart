import '../../app/state/planner_application_controller.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/planner/mastery_yields.dart';
import '../../domain/state/planner_state.dart';
import 'editor_models.dart';

const String editorCustomChoice = '\u0000custom';
const String editorNoMethodChoice = '';

final class EditorItemRecord {
  const EditorItemRecord({
    required this.name,
    required this.recipe,
    required this.category,
    required this.bundled,
  });

  final String name;
  final Recipe recipe;
  final String category;
  final bool bundled;
  bool get craftable => recipe.isCraftable;
}

final class RecipeEditorProjection {
  RecipeEditorProjection._({
    required this.items,
    required this.itemNames,
    required this.categories,
    required this.methods,
    required this.typeChoices,
  });

  factory RecipeEditorProjection.fromController(
    ModeFeatureController controller,
  ) {
    final recipes = controller.recipes;
    final bundledNames = controller.owner.catalog
        .forMode(controller.mode)
        .items
        .keys;
    final records =
        <EditorItemRecord>[
          for (final entry in recipes.entries)
            EditorItemRecord(
              name: entry.key,
              recipe: entry.value,
              category: categoryForRecipe(entry.value),
              bundled: containsFolded(bundledNames, entry.key),
            ),
        ]..sort((left, right) {
          final craftable = right.craftable.toString().compareTo(
            left.craftable.toString(),
          );
          if (craftable != 0) return craftable;
          return compareEditorNames(left.name, right.name);
        });

    final categoryValues = <String>[
      for (final item in records) item.category,
      ...controller.state.value.customCategories,
      ...controller.state.value.ingredientMeta.values
          .map((metadata) => metadata.category)
          .whereType<String>(),
    ];
    final categories = distinctEditorValues(categoryValues)
      ..sort(compareEditorNames);
    final methods = distinctEditorValues(<String>[
      ...processingMethods,
      ...recipes.values.map((recipe) => recipe.method).whereType<String>(),
    ])..sort(compareEditorNames);

    return RecipeEditorProjection._(
      items: List<EditorItemRecord>.unmodifiable(records),
      itemNames: List<String>.unmodifiable(records.map((item) => item.name)),
      categories: List<String>.unmodifiable(categories),
      methods: List<String>.unmodifiable(methods),
      typeChoices: List<EditorTypeChoice>.unmodifiable(
        editorTypeChoices(controller.mode.key),
      ),
    );
  }

  final List<EditorItemRecord> items;
  final List<String> itemNames;
  final List<String> categories;
  final List<String> methods;
  final List<EditorTypeChoice> typeChoices;

  List<EditorItemRecord> filtered(String search) {
    final query = search.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items
        .where((item) => item.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  String? canonicalItemName(String value) => foldedValue(itemNames, value);
}

final class EditorTypeChoice {
  const EditorTypeChoice(this.value, this.label);
  final String value;
  final String label;
}

List<EditorTypeChoice> editorTypeChoices(String mode) => switch (mode) {
  'cooking' => const <EditorTypeChoice>[
    EditorTypeChoice('cooking', 'Residence Cooking'),
    EditorTypeChoice('processing', 'Processing'),
    EditorTypeChoice('gathered', 'Base Item'),
  ],
  'processing' => const <EditorTypeChoice>[
    EditorTypeChoice('processing', 'Processing'),
    EditorTypeChoice('simple_alchemy', 'Simple Alchemy'),
    EditorTypeChoice('cooking', 'Simple Cooking'),
    EditorTypeChoice('gathered', 'Base Item'),
  ],
  _ => const <EditorTypeChoice>[
    EditorTypeChoice('alchemy', 'Residence Alchemy'),
    EditorTypeChoice('simple_alchemy', 'Simple Alchemy'),
    EditorTypeChoice('cooking', 'Residence Cooking'),
    EditorTypeChoice('processing', 'Processing'),
    EditorTypeChoice('gathered', 'Base Item'),
  ],
};

String categoryForRecipe(Recipe recipe) {
  final group = recipe.group?.trim();
  if (group != null && group.isNotEmpty) return normalizeEditorCategory(group);
  return recipe.hasRecordedRecipe ? 'Crafted' : 'Base Items';
}

RecipeState stateFromRecipe(Recipe source) => RecipeState(
  type: source.type,
  baseOutput: source.baseOutput,
  role: source.role,
  group: source.group,
  method: source.method,
  ingredients: <IngredientState>[
    for (final ingredient in source.ingredients)
      IngredientState(
        name: ingredient.name,
        quantity: ingredient.quantity,
        options: ingredient.options,
        substituteGroup: ingredient.substituteGroup,
        substituteRatios: ingredient.substituteRatios,
      ),
  ],
  marketId: source.marketId,
  sourceNote: source.sourceNote,
  vendor: source.vendor,
  location: source.location,
  npcPrice: source.npcPrice,
  qualityBase: source.qualityBase,
  qualityGrade: source.qualityGrade,
  outputMinimum: source.outputMinimum,
  outputMaximum: source.outputMaximum,
);

MapEntry<String, T>? foldedEntry<T>(Map<String, T> values, String name) {
  final exact = values.entries.where((entry) => entry.key == name);
  if (exact.isNotEmpty) return exact.first;
  for (final entry in values.entries) {
    if (sameEditorName(entry.key, name)) return entry;
  }
  return null;
}

String? foldedValue(Iterable<String> values, String name) {
  for (final value in values) {
    if (value == name) return value;
  }
  for (final value in values) {
    if (sameEditorName(value, name)) return value;
  }
  return null;
}

bool containsFolded(Iterable<String> values, String name) =>
    foldedValue(values, name) != null;

bool sameEditorName(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();

int compareEditorNames(String left, String right) {
  final folded = left.toLowerCase().compareTo(right.toLowerCase());
  return folded == 0 ? left.compareTo(right) : folded;
}

List<String> distinctEditorValues(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in values) {
    final value = normalizeEditorCategory(raw);
    if (value.isEmpty || !seen.add(value.toLowerCase())) continue;
    result.add(value);
  }
  return result;
}
