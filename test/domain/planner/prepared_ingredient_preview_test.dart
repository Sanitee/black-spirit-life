import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart'
    as saved;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = PlannerEngine();
  test(
    'prepared previews exactly match ordinary previews across real formulas',
    () {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      const assembly = PlannerAssembly();
      final rules = assembly.plannerRules(catalog.supportingData);
      var checked = 0;
      for (final mode in CraftMode.values) {
        final recipes = assembly.assembleRecipes(
          catalog: catalog.forMode(mode),
          state: saved.ModeState(
            target: '',
            bonusTarget: '',
            market: saved.MarketState(),
            appearance: saved.AppearanceSettings.defaultsFor(mode),
          ),
          supportingData: catalog.supportingData,
          sharedMetadata: catalog.alchemy.metadata,
          mode: mode,
        );
        for (final recipe in recipes.values.where(
          (r) => r.isCraftable && r.type == mode.key,
        )) {
          for (final variant in [null, ...recipe.variants]) {
            final formula = recipe.resolveVariant(variant?.id);
            final overlay = {...recipes, formula.name: formula};
            final choices = {if (variant != null) formula.name: variant.id};
            final prepared = engine.prepareIngredientPreview(
              recipes: overlay,
              state: PlannerState(
                target: formula.name,
                recipeVariantChoices: choices,
              ),
              rules: rules,
            );
            for (final ingredient in formula.ingredients) {
              // Exercise saved and automatic substitutes, every quality family,
              // stock/inventory decisions and repeated reuse of the same index.
              for (final grade in ['normal', 'high', 'special', 'blue']) {
                final option = ingredient.options.lastOrNull ?? ingredient.name;
                final state = PlannerState(
                  target: formula.name,
                  recipeVariantChoices: choices,
                  inventory: {option: 7},
                  marketPrices: {option: 100},
                  marketStock: {option: 2},
                  ingredientGrades: {
                    'recipe:${formula.name}:${ingredient.name}': grade,
                  },
                  substituteChoices: {
                    if (grade != 'normal')
                      'recipe:${formula.name}:${ingredient.substituteGroup ?? ingredient.name}':
                          option,
                  },
                );
                final ordinary = engine.previewIngredientSelection(
                  recipes: overlay,
                  state: state,
                  parentName: formula.name,
                  ingredient: ingredient,
                  rules: rules,
                );
                final cached = prepared.preview(
                  state: state,
                  parentName: formula.name,
                  ingredient: ingredient,
                );
                expect(
                  _fields(cached),
                  _fields(ordinary),
                  reason:
                      '${mode.key}/${formula.name}/${ingredient.name}/$grade',
                );
                checked++;
              }
            }
          }
        }
      }
      expect(checked, greaterThan(8000));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('a changed variant selection uses the ordinary safe path', () {
    final ingredient = _ingredient();
    final recipe = _recipe('Target', [ingredient]);
    final recipes = {'Target': recipe, 'Raw': _recipe('Raw', [])};
    final prepared = engine.prepareIngredientPreview(
      recipes: recipes,
      state: PlannerState(target: 'Target'),
    );
    final state = PlannerState(
      target: 'Target',
      recipeVariantChoices: {'Target': 'changed'},
      inventory: {'Raw': 3},
    );
    expect(
      _fields(
        prepared.preview(
          state: state,
          parentName: 'Target',
          ingredient: ingredient,
        ),
      ),
      _fields(
        engine.previewIngredientSelection(
          recipes: recipes,
          state: state,
          parentName: 'Target',
          ingredient: ingredient,
        ),
      ),
    );
  });

  test('prepared snapshots preserve the existing collision rejection', () {
    final recipes = {'Raw': _recipe('Raw', []), 'raw': _recipe('raw', [])};
    final state = PlannerState(target: 'Target');
    expect(
      () => engine.prepareIngredientPreview(recipes: recipes, state: state),
      throwsArgumentError,
    );
    expect(
      () => engine.previewIngredientSelection(
        recipes: recipes,
        state: state,
        parentName: 'Target',
        ingredient: _ingredient(),
      ),
      throwsArgumentError,
    );
  });
}

List<Object?> _fields(PlanStepIngredient value) => [
  value.key,
  value.name,
  value.original,
  value.substituteGroup,
  value.baseName,
  value.grade,
  value.options,
  value.parentName,
  value.need,
  value.have,
  value.missing,
  value.craftable,
];

Ingredient _ingredient() => Ingredient(
  name: 'Raw',
  quantity: 2,
  options: const [],
  substituteGroup: null,
  substituteRatios: const {},
);
Recipe _recipe(String name, List<Ingredient> ingredients) => Recipe(
  name: name,
  type: 'cooking',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: ingredients,
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 4,
);
