import 'package:bdo_craft_planner_flutter/domain/planner/ingredient_quality.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rules = PlannerRules(
    qualityIngredients: const <String>{'Sunrise Herb'},
    qualityConversions: const <String, QualityConversionRule>{
      'Silver Azalea': QualityConversionRule(
        high: QualityTierRule(name: 'Choice Silver Azalea', ratio: 4),
        special: QualityTierRule(name: 'Rare Silver Azalea', ratio: 6),
      ),
    },
    blueElixirMap: const <String, String>{'Elixir': 'Blue Elixir'},
    cookingSpecialMap: const <String, SpecialQualityRule>{
      'Meal': SpecialQualityRule(name: 'Special Meal', ratio: 2.5),
    },
  );

  test('explicit material conversions retain names and effective ratios', () {
    final alternatives = ingredientQualityAlternatives(
      rules: rules,
      ingredientName: 'silver azalea',
    );

    expect(alternatives.map((alternative) => alternative.grade), <String>[
      'high',
      'special',
    ]);
    final high = _byGrade(alternatives, 'high');
    expect(high.name, 'Choice Silver Azalea');
    expect(high.ratio, 4);
    expect(high.requiredQuantityFactor, 0.25);
    expect(high.requiredQuantityFor(10), 3);

    final special = _byGrade(alternatives, 'special');
    expect(special.name, 'Rare Silver Azalea');
    expect(special.ratio, 6);
    expect(special.requiredQuantityFactor, closeTo(1 / 6, 0.0000001));
    expect(special.requiredQuantityFor(10), 2);
    expect(special.requiredQuantityFor(-10), 0);
  });

  test('quality ingredients receive the planner fallback names and ratios', () {
    final alternatives = ingredientQualityAlternatives(
      rules: rules,
      ingredientName: 'Sunrise Herb',
    );

    final high = _byGrade(alternatives, 'high');
    expect(high.name, 'High-Quality Sunrise Herb');
    expect(high.ratio, 3);
    expect(high.requiredQuantityFor(10), 4);

    final special = _byGrade(alternatives, 'special');
    expect(special.name, 'Special Sunrise Herb');
    expect(special.ratio, 5);
    expect(special.requiredQuantityFor(10), 2);
  });

  test('blank configured material names fall back without losing ratios', () {
    final alternatives = ingredientQualityAlternatives(
      rules: PlannerRules(
        qualityConversions: const <String, QualityConversionRule>{
          'Pepper': QualityConversionRule(
            high: QualityTierRule(name: ' ', ratio: 4),
            special: QualityTierRule(name: '', ratio: 8),
          ),
        },
      ),
      ingredientName: 'Pepper',
    );

    expect(_byGrade(alternatives, 'high').name, 'High-Quality Pepper');
    expect(_byGrade(alternatives, 'high').ratio, 4);
    expect(_byGrade(alternatives, 'special').name, 'Special Pepper');
    expect(_byGrade(alternatives, 'special').ratio, 8);
  });

  test('ordinary mushrooms get fallbacks while special forms do not', () {
    final alternatives = ingredientQualityAlternatives(
      rules: PlannerRules(),
      ingredientName: 'Button Mushroom',
    );
    expect(alternatives.map((alternative) => alternative.name), <String>[
      'High-Quality Button Mushroom',
      'Special Button Mushroom',
    ]);

    for (final name in <String>[
      'Truffle Mushroom',
      'High-Quality Button Mushroom',
      'Special Button Mushroom',
      'Big Button Mushroom',
      'Button Mushroom Hypha',
    ]) {
      expect(
        ingredientQualityAlternatives(
          rules: PlannerRules(),
          ingredientName: name,
        ),
        isEmpty,
        reason: '$name must not recursively expose mushroom fallbacks',
      );
    }
  });

  test('blue elixirs, Refined Oatmeal, and cooking specials keep ratios', () {
    final elixir = _byGrade(
      ingredientQualityAlternatives(rules: rules, ingredientName: 'ELIXIR'),
      'blue',
    );
    expect(elixir.name, 'Blue Elixir');
    expect(elixir.ratio, 3);
    expect(elixir.requiredQuantityFor(10), 4);

    final oatmeal = _byGrade(
      ingredientQualityAlternatives(rules: rules, ingredientName: 'oatmeal'),
      'blue',
    );
    expect(oatmeal.name, 'Refined Oatmeal');
    expect(oatmeal.ratio, 2);
    expect(oatmeal.requiredQuantityFor(5), 3);

    final meal = _byGrade(
      ingredientQualityAlternatives(rules: rules, ingredientName: 'meal'),
      'blue',
    );
    expect(meal.name, 'Special Meal');
    expect(meal.ratio, 2.5);
    expect(meal.requiredQuantityFor(6), 3);

    expect(
      ingredientQualityAlternatives(rules: rules, ingredientName: ' oatmeal '),
      isEmpty,
      reason: 'recipe-name matching preserves the engine whitespace semantics',
    );
  });

  test('blue-map precedence and the planner minimum ratio are preserved', () {
    final precedence = _byGrade(
      ingredientQualityAlternatives(
        rules: PlannerRules(
          blueElixirMap: const <String, String>{
            'Oatmeal': 'Mapped Blue Oatmeal',
          },
          cookingSpecialMap: const <String, SpecialQualityRule>{
            'Oatmeal': SpecialQualityRule(
              name: 'Configured Special Oatmeal',
              ratio: 9,
            ),
          },
        ),
        ingredientName: 'Oatmeal',
      ),
      'blue',
    );
    expect(precedence.name, 'Mapped Blue Oatmeal');
    expect(precedence.ratio, 3);

    final clamped = _byGrade(
      ingredientQualityAlternatives(
        rules: PlannerRules(
          cookingSpecialMap: const <String, SpecialQualityRule>{
            'Meal': SpecialQualityRule(name: 'Special Meal', ratio: 0),
          },
        ),
        ingredientName: 'Meal',
      ),
      'blue',
    );
    expect(clamped.ratio, 0.0001);
    expect(clamped.requiredQuantityFor(1), 10000);
  });

  test('unrelated ingredients have no higher-grade alternatives', () {
    expect(
      ingredientQualityAlternatives(
        rules: rules,
        ingredientName: 'Black Stone',
      ),
      isEmpty,
    );
  });

  test('profiles cover material, blue-family, and mushroom rules', () {
    expect(
      ingredientQualityProfile(
        rules: rules,
        parentIsProcessing: false,
        ingredientName: 'sunrise herb',
      ).grades,
      const <String>['normal', 'high', 'special'],
    );
    expect(
      ingredientQualityProfile(
        rules: rules,
        parentIsProcessing: false,
        ingredientName: 'Silver Azalea',
      ).grades,
      const <String>['normal', 'high', 'special'],
    );
    expect(
      ingredientQualityProfile(
        rules: rules,
        parentIsProcessing: false,
        ingredientName: 'Button Mushroom',
      ).grades,
      const <String>['normal', 'high', 'special'],
    );
    for (final name in <String>['ELIXIR', 'Oatmeal', 'meal']) {
      expect(
        ingredientQualityProfile(
          rules: rules,
          parentIsProcessing: false,
          ingredientName: name,
        ).grades,
        const <String>['normal', 'blue'],
      );
    }
  });

  test('processing parents expose no grade choices', () {
    expect(
      ingredientQualityAlternatives(
        rules: rules,
        ingredientName: 'Sunrise Herb',
      ),
      isNotEmpty,
      reason: 'the pure enumerator leaves processing suppression to callers',
    );
    expect(
      ingredientQualityProfile(
        rules: rules,
        parentIsProcessing: true,
        ingredientName: 'Sunrise Herb',
      ).grades,
      isEmpty,
    );
  });

  test('selection normalizes scoped and legacy values against the profile', () {
    expect(
      selectedIngredientQualityGrade(
        rules: rules,
        parentIsProcessing: false,
        parentName: 'Target',
        originalIngredientName: 'Wild Herbs',
        selectedIngredientName: 'Elixir',
        savedGrades: const <String, String>{
          'recipe:target:wild herbs': ' BLUE ',
          'Elixir': 'normal',
        },
      ),
      'blue',
    );
    expect(
      selectedIngredientQualityGrade(
        rules: rules,
        parentIsProcessing: false,
        parentName: 'Target',
        originalIngredientName: 'Elixir',
        selectedIngredientName: 'Elixir',
        savedGrades: const <String, String>{'ELIXIR': 'special'},
      ),
      'normal',
    );
  });
}

IngredientQualityAlternative _byGrade(
  List<IngredientQualityAlternative> alternatives,
  String grade,
) {
  return alternatives.singleWhere((alternative) => alternative.grade == grade);
}
