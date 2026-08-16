import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/planner/ingredient_quality.dart';
import '../../domain/planner/planner_models.dart';

enum RecipeBookUseKind {
  requiredIngredient('Required'),
  substitute('Substitute'),
  qualitySubstitute('Higher grade');

  const RecipeBookUseKind(this.label);

  final String label;
}

final class RecipeBookUseMatch {
  const RecipeBookUseMatch({
    required this.kind,
    required this.sourceName,
    required this.ingredientName,
    required this.selectedIngredientName,
    required this.originalQuantity,
    required this.sourceQuantity,
    required this.substituteRatio,
    required this.qualityRatio,
    required this.grade,
  });

  final RecipeBookUseKind kind;
  final String sourceName;
  final String ingredientName;
  final String selectedIngredientName;
  final double originalQuantity;
  final double sourceQuantity;
  final double substituteRatio;
  final double qualityRatio;
  final String grade;
}

final class RecipeBookUseRoute {
  RecipeBookUseRoute({
    required this.id,
    required this.variantId,
    required this.routeId,
    required this.routeLabel,
    required this.batchMultiplier,
    required this.type,
    required this.method,
    required this.baseOutput,
    required this.outputMinimum,
    required this.outputMaximum,
    required Iterable<Ingredient> ingredients,
    required Iterable<RecipeBookUseMatch> matches,
  }) : ingredients = List<Ingredient>.unmodifiable(ingredients),
       matches = List<RecipeBookUseMatch>.unmodifiable(matches);

  final String id;
  final String? variantId;
  final String routeId;
  final String routeLabel;
  final int batchMultiplier;
  final String type;
  final String? method;
  final double baseOutput;
  final double? outputMinimum;
  final double? outputMaximum;
  final List<Ingredient> ingredients;
  final List<RecipeBookUseMatch> matches;

  Set<RecipeBookUseKind> get kinds =>
      Set<RecipeBookUseKind>.unmodifiable(matches.map((match) => match.kind));
}

final class RecipeBookUseEntry {
  RecipeBookUseEntry({
    required this.mode,
    required this.name,
    required this.recipe,
    required this.hidden,
    required Iterable<RecipeBookUseRoute> routes,
  }) : routes = List<RecipeBookUseRoute>.unmodifiable(routes);

  final CraftMode mode;
  final String name;
  final Recipe recipe;
  final bool hidden;
  final List<RecipeBookUseRoute> routes;

  Set<RecipeBookUseKind> get kinds => Set<RecipeBookUseKind>.unmodifiable(
    routes.expand((route) => route.matches).map((match) => match.kind),
  );

  RecipeBookUseRoute? preferredRoute(String? selectedVariantId) {
    final selected = _fold(selectedVariantId ?? '');
    if (selected.isNotEmpty) {
      for (final route in routes) {
        if (_fold(route.variantId ?? '') == selected) return route;
      }
    }
    for (final route in routes) {
      if (route.batchMultiplier == 1) return route;
    }
    return routes.isEmpty ? null : routes.first;
  }

  String? preferredVariantId(String? selectedVariantId) =>
      preferredRoute(selectedVariantId)?.variantId;
}

final class RecipeBookUseSnapshot {
  RecipeBookUseSnapshot({
    required this.itemName,
    required Iterable<RecipeBookUseEntry> entries,
  }) : entries = List<RecipeBookUseEntry>.unmodifiable(entries);

  final String itemName;
  final List<RecipeBookUseEntry> entries;

  int get recipeCount => entries.length;

  Map<CraftMode, int> get modeCounts => Map<CraftMode, int>.unmodifiable({
    for (final mode in CraftMode.values)
      if (entries.any((entry) => entry.mode == mode))
        mode: entries.where((entry) => entry.mode == mode).length,
  });
}

/// Reverse recipe graph used by the Recipe Book's compact "Used In" panel.
///
/// Variants replace the base formula as a complete route, so recipes with
/// recorded variants index those variants only. Each output recipe is counted
/// once even when an ingredient appears in several routes or batch sizes.
final class RecipeBookUsageIndex {
  RecipeBookUsageIndex._(this._entriesByItem);

  factory RecipeBookUsageIndex.build({
    required Map<CraftMode, Map<String, Recipe>> recipesByMode,
    required PlannerRules rules,
    Map<CraftMode, Set<String>> hiddenNamesByMode =
        const <CraftMode, Set<String>>{},
  }) {
    final builders = <String, Map<String, _UseEntryBuilder>>{};

    for (final mode in CraftMode.values) {
      final recipes = recipesByMode[mode] ?? const <String, Recipe>{};
      final availableNames = recipes.keys.map(_fold).toSet();
      final unavailableNames = rules.legacyUnavailableItems.map(_fold).toSet();
      final hiddenNames = hiddenNamesByMode[mode] ?? const <String>{};
      for (final recipeEntry in recipes.entries) {
        final recipe = recipeEntry.value;
        if (!recipe.isCraftable) continue;
        final formulas = recipe.variants.isEmpty
            ? <_Formula>[_Formula.base(recipe)]
            : recipe.variants.map(_Formula.variant);
        for (final formula in formulas) {
          final matchesByItem = _matchesForFormula(
            formula.ingredients,
            rules,
            allowQualitySubstitutes: _fold(formula.type) != 'processing',
            availableNames: availableNames,
            unavailableNames: unavailableNames,
          );
          for (final matched in matchesByItem.entries) {
            if (_sameName(matched.key, recipeEntry.key)) continue;
            final entryKey = '${mode.key}\u0000${_fold(recipeEntry.key)}';
            final entryBuilder = builders
                .putIfAbsent(matched.key, () => <String, _UseEntryBuilder>{})
                .putIfAbsent(
                  entryKey,
                  () => _UseEntryBuilder(
                    mode: mode,
                    name: recipeEntry.key,
                    recipe: recipe,
                    hidden: hiddenNames.contains(_fold(recipeEntry.key)),
                  ),
                );
            entryBuilder.addRoute(formula, matched.value);
          }
        }
      }
    }

    return RecipeBookUsageIndex._(
      Map<String, List<RecipeBookUseEntry>>.unmodifiable({
        for (final item in builders.entries)
          item.key: List<RecipeBookUseEntry>.unmodifiable(
            item.value.values.map((builder) => builder.build()),
          ),
      }),
    );
  }

  final Map<String, List<RecipeBookUseEntry>> _entriesByItem;

  RecipeBookUseSnapshot snapshotFor(
    String itemName, {
    required CraftMode currentMode,
  }) {
    final entries =
        List<RecipeBookUseEntry>.of(
          _entriesByItem[_fold(itemName)] ?? const <RecipeBookUseEntry>[],
        )..sort((left, right) {
          final leftCurrent = left.mode == currentMode;
          final rightCurrent = right.mode == currentMode;
          if (leftCurrent != rightCurrent) return leftCurrent ? -1 : 1;
          final modeOrder = left.mode.index.compareTo(right.mode.index);
          if (modeOrder != 0) return modeOrder;
          return _compareNames(left.name, right.name);
        });
    return RecipeBookUseSnapshot(itemName: itemName, entries: entries);
  }
}

final class _Formula {
  const _Formula({
    required this.id,
    required this.variantId,
    required this.routeId,
    required this.routeLabel,
    required this.batchMultiplier,
    required this.type,
    required this.method,
    required this.baseOutput,
    required this.outputMinimum,
    required this.outputMaximum,
    required this.ingredients,
  });

  factory _Formula.base(Recipe recipe) => _Formula(
    id: 'base',
    variantId: null,
    routeId: 'base',
    routeLabel: 'Standard',
    batchMultiplier: 1,
    type: recipe.type,
    method: recipe.method,
    baseOutput: recipe.baseOutput,
    outputMinimum: recipe.outputMinimum,
    outputMaximum: recipe.outputMaximum,
    ingredients: recipe.ingredients,
  );

  factory _Formula.variant(RecipeVariant variant) => _Formula(
    id: variant.id,
    variantId: variant.id,
    routeId: variant.routeId,
    routeLabel: variant.label,
    batchMultiplier: variant.batchMultiplier,
    type: variant.type,
    method: variant.method,
    baseOutput: variant.baseOutput,
    outputMinimum: variant.outputMinimum,
    outputMaximum: variant.outputMaximum,
    ingredients: variant.ingredients,
  );

  final String id;
  final String? variantId;
  final String routeId;
  final String routeLabel;
  final int batchMultiplier;
  final String type;
  final String? method;
  final double baseOutput;
  final double? outputMinimum;
  final double? outputMaximum;
  final List<Ingredient> ingredients;
}

final class _UseEntryBuilder {
  _UseEntryBuilder({
    required this.mode,
    required this.name,
    required this.recipe,
    required this.hidden,
  });

  final CraftMode mode;
  final String name;
  final Recipe recipe;
  final bool hidden;
  final Map<String, _UseRouteBuilder> routes = <String, _UseRouteBuilder>{};

  void addRoute(_Formula formula, Iterable<RecipeBookUseMatch> matches) {
    final routeKey = _fold(formula.id);
    routes
        .putIfAbsent(routeKey, () => _UseRouteBuilder(formula))
        .addMatches(matches);
  }

  RecipeBookUseEntry build() {
    final builtRoutes = routes.values.map((builder) => builder.build()).toList()
      ..sort((left, right) {
        final route = _compareNames(left.routeLabel, right.routeLabel);
        if (route != 0) return route;
        return left.batchMultiplier.compareTo(right.batchMultiplier);
      });
    return RecipeBookUseEntry(
      mode: mode,
      name: name,
      recipe: recipe,
      hidden: hidden,
      routes: builtRoutes,
    );
  }
}

final class _UseRouteBuilder {
  _UseRouteBuilder(this.formula);

  final _Formula formula;
  final Map<String, RecipeBookUseMatch> matches =
      <String, RecipeBookUseMatch>{};

  void addMatches(Iterable<RecipeBookUseMatch> values) {
    for (final value in values) {
      final key = _fold(value.ingredientName);
      final existing = matches[key];
      if (existing == null ||
          _kindPriority(value.kind) < _kindPriority(existing.kind)) {
        matches[key] = value;
      }
    }
  }

  RecipeBookUseRoute build() => RecipeBookUseRoute(
    id: formula.id,
    variantId: formula.variantId,
    routeId: formula.routeId,
    routeLabel: formula.routeLabel,
    batchMultiplier: formula.batchMultiplier,
    type: formula.type,
    method: formula.method,
    baseOutput: formula.baseOutput,
    outputMinimum: formula.outputMinimum,
    outputMaximum: formula.outputMaximum,
    ingredients: formula.ingredients,
    matches: matches.values,
  );
}

Map<String, List<RecipeBookUseMatch>> _matchesForFormula(
  Iterable<Ingredient> ingredients,
  PlannerRules rules, {
  required bool allowQualitySubstitutes,
  required Set<String> availableNames,
  required Set<String> unavailableNames,
}) {
  final matches = <String, Map<String, RecipeBookUseMatch>>{};

  void add({
    required String itemName,
    required Ingredient ingredient,
    required String selectedIngredientName,
    required RecipeBookUseKind kind,
    required double substituteRatio,
    required double qualityRatio,
    required String grade,
  }) {
    final itemKey = _fold(itemName);
    final ingredientKey = _fold(ingredient.name);
    if (itemKey.isEmpty || ingredientKey.isEmpty) return;
    final itemMatches = matches.putIfAbsent(
      itemKey,
      () => <String, RecipeBookUseMatch>{},
    );
    final existing = itemMatches[ingredientKey];
    if (existing == null ||
        _kindPriority(kind) < _kindPriority(existing.kind)) {
      itemMatches[ingredientKey] = RecipeBookUseMatch(
        kind: kind,
        sourceName: itemName,
        ingredientName: ingredient.name,
        selectedIngredientName: selectedIngredientName,
        originalQuantity: ingredient.quantity,
        sourceQuantity: qualityRatio == 1
            ? ingredient.quantity * substituteRatio
            : (ingredient.quantity * substituteRatio / qualityRatio)
                  .ceilToDouble(),
        substituteRatio: substituteRatio,
        qualityRatio: qualityRatio,
        grade: grade,
      );
    }
  }

  for (final ingredient in ingredients) {
    add(
      itemName: ingredient.name,
      ingredient: ingredient,
      selectedIngredientName: ingredient.name,
      kind: RecipeBookUseKind.requiredIngredient,
      substituteRatio: _substituteRatio(ingredient, ingredient.name),
      qualityRatio: 1,
      grade: 'normal',
    );
    final acceptedNames = <String>{ingredient.name, ...ingredient.options};
    for (final option in acceptedNames) {
      if (!_sameName(option, ingredient.name) &&
          (!availableNames.contains(_fold(option)) ||
              unavailableNames.contains(_fold(option)))) {
        continue;
      }
      if (!_sameName(option, ingredient.name)) {
        add(
          itemName: option,
          ingredient: ingredient,
          selectedIngredientName: option,
          kind: RecipeBookUseKind.substitute,
          substituteRatio: _substituteRatio(ingredient, option),
          qualityRatio: 1,
          grade: 'normal',
        );
      }
      if (allowQualitySubstitutes) {
        for (final alternate in ingredientQualityAlternatives(
          rules: rules,
          ingredientName: option,
        )) {
          add(
            itemName: alternate.name,
            ingredient: ingredient,
            selectedIngredientName: option,
            kind: RecipeBookUseKind.qualitySubstitute,
            substituteRatio: _substituteRatio(ingredient, option),
            qualityRatio: alternate.ratio,
            grade: alternate.grade,
          );
        }
      }
    }
  }

  return <String, List<RecipeBookUseMatch>>{
    for (final entry in matches.entries)
      entry.key: List<RecipeBookUseMatch>.unmodifiable(entry.value.values),
  };
}

double _substituteRatio(Ingredient ingredient, String selectedName) {
  for (final entry in ingredient.substituteRatios.entries) {
    if (_sameName(entry.key, selectedName)) {
      return entry.value < 0.0001 ? 0.0001 : entry.value;
    }
  }
  return 1;
}

int _kindPriority(RecipeBookUseKind kind) => switch (kind) {
  RecipeBookUseKind.requiredIngredient => 0,
  RecipeBookUseKind.qualitySubstitute => 1,
  RecipeBookUseKind.substitute => 2,
};

String _fold(String value) => value.trim().toLowerCase();

bool _sameName(String left, String right) => _fold(left) == _fold(right);

int _compareNames(String left, String right) {
  final folded = _fold(left).compareTo(_fold(right));
  return folded != 0 ? folded : left.compareTo(right);
}
