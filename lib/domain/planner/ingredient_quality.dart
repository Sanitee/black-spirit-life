import 'planner_models.dart';

enum IngredientQualityFamily { none, material, blue }

final class IngredientQualityProfile {
  const IngredientQualityProfile._(this.family, this.grades);

  static const none = IngredientQualityProfile._(
    IngredientQualityFamily.none,
    <String>[],
  );
  static const material = IngredientQualityProfile._(
    IngredientQualityFamily.material,
    <String>['normal', 'high', 'special'],
  );
  static const blue = IngredientQualityProfile._(
    IngredientQualityFamily.blue,
    <String>['normal', 'blue'],
  );

  final IngredientQualityFamily family;
  final List<String> grades;
}

/// A higher-grade ingredient that can replace a normal-grade ingredient.
///
/// [ratio] is the number of normal-grade units covered by one unit of this
/// alternative. [requiredQuantityFactor] is its inverse for callers that need
/// to compare recipe requirements without rounding.
final class IngredientQualityAlternative {
  const IngredientQualityAlternative._({
    required this.grade,
    required this.name,
    required this.ratio,
  });

  final String grade;
  final String name;
  final double ratio;

  double get requiredQuantityFactor => 1 / ratio;

  double requiredQuantityFor(double normalQuantity) {
    final amount = normalQuantity < 0 ? 0.0 : normalQuantity;
    return (amount / ratio).ceilToDouble();
  }
}

/// Returns every higher-grade alternative supported by the planner rules.
///
/// Processing recipes decide separately whether quality substitution is
/// allowed; this pure enumerator intentionally has no parent-recipe context.
List<IngredientQualityAlternative> ingredientQualityAlternatives({
  required PlannerRules rules,
  required String ingredientName,
}) {
  final profile = ingredientQualityProfile(
    rules: rules,
    parentIsProcessing: false,
    ingredientName: ingredientName,
  );

  if (profile.family == IngredientQualityFamily.blue) {
    final blueElixirName = _mapValue(rules.blueElixirMap, ingredientName);
    if (blueElixirName != null) {
      return List<IngredientQualityAlternative>.unmodifiable(
        <IngredientQualityAlternative>[
          IngredientQualityAlternative._(
            grade: 'blue',
            name: blueElixirName,
            ratio: 3,
          ),
        ],
      );
    }
    if (_sameName(ingredientName, 'Oatmeal')) {
      return const <IngredientQualityAlternative>[
        IngredientQualityAlternative._(
          grade: 'blue',
          name: 'Refined Oatmeal',
          ratio: 2,
        ),
      ];
    }
    final cookingSpecial = _mapValue(rules.cookingSpecialMap, ingredientName);
    if (cookingSpecial != null && cookingSpecial.name.trim().isNotEmpty) {
      return List<IngredientQualityAlternative>.unmodifiable(
        <IngredientQualityAlternative>[
          IngredientQualityAlternative._(
            grade: 'blue',
            name: cookingSpecial.name,
            ratio: _effectiveRatio(cookingSpecial.ratio),
          ),
        ],
      );
    }
    return const <IngredientQualityAlternative>[];
  }

  if (profile.family != IngredientQualityFamily.material) {
    return const <IngredientQualityAlternative>[];
  }

  final conversion = _mapValue(rules.qualityConversions, ingredientName);
  return List<IngredientQualityAlternative>.unmodifiable(
    <IngredientQualityAlternative>[
      _materialAlternative(
        grade: 'high',
        fallbackName: 'High-Quality $ingredientName',
        fallbackRatio: 3,
        configured: conversion?.high,
      ),
      _materialAlternative(
        grade: 'special',
        fallbackName: 'Special $ingredientName',
        fallbackRatio: 5,
        configured: conversion?.special,
      ),
    ],
  );
}

IngredientQualityProfile ingredientQualityProfile({
  required PlannerRules rules,
  required bool parentIsProcessing,
  required String ingredientName,
}) {
  if (parentIsProcessing) return IngredientQualityProfile.none;
  if (_containsMapKey(rules.blueElixirMap, ingredientName) ||
      _sameName(ingredientName, 'Oatmeal') ||
      _containsMapKey(rules.cookingSpecialMap, ingredientName)) {
    return IngredientQualityProfile.blue;
  }
  final folded = _foldName(ingredientName);
  final isOrdinaryMushroom =
      folded.contains('mushroom') &&
      !folded.contains('truffle') &&
      !folded.contains('high-quality') &&
      !folded.contains('special') &&
      !folded.contains('big ') &&
      !folded.contains('hypha');
  if (_containsName(rules.qualityIngredients, ingredientName) ||
      _containsMapKey(rules.qualityConversions, ingredientName) ||
      isOrdinaryMushroom) {
    return IngredientQualityProfile.material;
  }
  return IngredientQualityProfile.none;
}

String selectedIngredientQualityGrade({
  required PlannerRules rules,
  required bool parentIsProcessing,
  required String parentName,
  required String originalIngredientName,
  required String selectedIngredientName,
  required Map<String, String> savedGrades,
}) {
  final profile = ingredientQualityProfile(
    rules: rules,
    parentIsProcessing: parentIsProcessing,
    ingredientName: selectedIngredientName,
  );
  final saved =
      _mapValue(savedGrades, 'recipe:$parentName:$originalIngredientName') ??
      _mapValue(savedGrades, selectedIngredientName);
  final normalized = normalizeIngredientQualityGrade(saved);
  return profile.grades.contains(normalized) ? normalized : 'normal';
}

String normalizeIngredientQualityGrade(String? value) {
  final normalized = _fold(value ?? '');
  return const <String>{
        'normal',
        'high',
        'special',
        'blue',
      }.contains(normalized)
      ? normalized
      : 'normal';
}

bool _sameName(String left, String right) =>
    _foldName(left) == _foldName(right);

String _fold(String value) => value.trim().toLowerCase();

String _foldName(String value) => value.toLowerCase();

bool _containsName(Iterable<String> values, String name) =>
    values.any((value) => _sameName(value, name));

bool _containsMapKey<T>(Map<String, T> values, String name) =>
    values.keys.any((value) => _sameName(value, name));

T? _mapValue<T>(Map<String, T> values, String name) {
  for (final entry in values.entries) {
    if (_sameName(entry.key, name)) return entry.value;
  }
  return null;
}

IngredientQualityAlternative _materialAlternative({
  required String grade,
  required String fallbackName,
  required double fallbackRatio,
  required QualityTierRule? configured,
}) {
  return IngredientQualityAlternative._(
    grade: grade,
    name: configured == null || configured.name.trim().isEmpty
        ? fallbackName
        : configured.name,
    ratio: _effectiveRatio(configured?.ratio ?? fallbackRatio),
  );
}

double _effectiveRatio(double ratio) => ratio < 0.0001 ? 0.0001 : ratio;
