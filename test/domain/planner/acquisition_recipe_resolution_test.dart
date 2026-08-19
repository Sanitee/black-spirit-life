import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/acquisition_recipe_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every production mode context prefers a real cross-workstation recipe '
      'over an empty leaf', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    const assembly = PlannerAssembly();
    final recipesByMode = <CraftMode, Map<String, Recipe>>{
      for (final mode in CraftMode.values)
        mode: assembly.assembleRecipes(
          catalog: catalog.forMode(mode),
          state: _modeState(mode),
          supportingData: catalog.supportingData,
          sharedMetadata: catalog.alchemy.metadata,
          mode: mode,
        ),
    };
    final failures = <String>[];
    final maskedContexts = <String>[];

    for (final currentMode in CraftMode.values) {
      final currentRecipes = recipesByMode[currentMode]!;
      for (final entry in currentRecipes.entries) {
        if (entry.value.isCraftable) continue;
        final crossModeHasRecipe = CraftMode.values
            .where((mode) => mode != currentMode)
            .map((mode) => _foldedRecipe(recipesByMode[mode]!, entry.key))
            .whereType<Recipe>()
            .any((recipe) => recipe.isCraftable);
        if (!crossModeHasRecipe) continue;

        final context = '${currentMode.key}:${entry.key}';
        maskedContexts.add(context);
        final resolved = resolveAcquisitionRecipe(
          name: entry.key,
          currentMode: currentMode,
          recipesByMode: recipesByMode,
        );
        if (resolved == null || !resolved.recipe.isCraftable) {
          failures.add(context);
        }
      }
    }

    expect(maskedContexts, hasLength(143));
    expect(maskedContexts, contains('processing:Elixir of Seal'));
    expect(maskedContexts, contains('alchemy:Magical Olivine Powder'));
    expect(
      maskedContexts.where(
        (context) => context.toLowerCase().endsWith(':perilla oil'),
      ),
      isNotEmpty,
    );
    expect(failures, isEmpty);
  });

  test('suppressed workstation tombstones cannot win resolution', () {
    final recipesByMode = <CraftMode, Map<String, Recipe>>{
      CraftMode.alchemy: <String, Recipe>{
        'Shared Item': _recipe('Shared Item', 'alchemy', 'Alchemy'),
      },
      CraftMode.cooking: <String, Recipe>{},
      CraftMode.processing: <String, Recipe>{
        'Shared Item': _recipe('Shared Item', 'processing', 'Heating'),
      },
    };

    final resolved = resolveAcquisitionRecipe(
      name: 'shared item',
      currentMode: CraftMode.alchemy,
      recipesByMode: recipesByMode,
      suppressedModes: const <CraftMode>{CraftMode.alchemy},
    );

    expect(resolved?.mode, CraftMode.processing);
    expect(resolved?.recipe.method, 'Heating');
  });

  test('current workstation craftable edit keeps precedence', () {
    final recipesByMode = <CraftMode, Map<String, Recipe>>{
      CraftMode.alchemy: <String, Recipe>{
        'Shared Item': _recipe('Shared Item', 'alchemy', 'Custom Alchemy'),
      },
      CraftMode.cooking: <String, Recipe>{},
      CraftMode.processing: <String, Recipe>{
        'Shared Item': _recipe('Shared Item', 'processing', 'Heating'),
      },
    };

    final resolved = resolveAcquisitionRecipe(
      name: 'shared item',
      currentMode: CraftMode.alchemy,
      recipesByMode: recipesByMode,
    );

    expect(resolved?.mode, CraftMode.alchemy);
    expect(resolved?.recipe.method, 'Custom Alchemy');
  });

  for (final role in const <RecipeRole>[
    RecipeRole.manualConversion,
    RecipeRole.salvage,
  ]) {
    test('$role recipes are not offered as acquisition routes', () {
      final recipesByMode = <CraftMode, Map<String, Recipe>>{
        CraftMode.alchemy: <String, Recipe>{},
        CraftMode.cooking: <String, Recipe>{},
        CraftMode.processing: <String, Recipe>{
          'Recovered Material': _recipe(
            'Recovered Material',
            'processing',
            'Heating',
            role: role,
          ),
        },
      };

      final resolved = resolveAcquisitionRecipe(
        name: 'Recovered Material',
        currentMode: CraftMode.processing,
        recipesByMode: recipesByMode,
      );

      expect(resolved, isNull);
    });
  }

  test('production route outranks a current-mode manual conversion', () {
    final recipesByMode = <CraftMode, Map<String, Recipe>>{
      CraftMode.alchemy: <String, Recipe>{
        'Shared Material': _recipe(
          'Shared Material',
          'alchemy',
          'Manual Exchange',
          role: RecipeRole.manualConversion,
        ),
      },
      CraftMode.cooking: <String, Recipe>{},
      CraftMode.processing: <String, Recipe>{
        'Shared Material': _recipe('Shared Material', 'processing', 'Heating'),
      },
    };

    final resolved = resolveAcquisitionRecipe(
      name: 'Shared Material',
      currentMode: CraftMode.alchemy,
      recipesByMode: recipesByMode,
    );

    expect(resolved?.mode, CraftMode.processing);
    expect(resolved?.recipe.role, RecipeRole.production);
  });
}

ModeState _modeState(CraftMode mode) => ModeState(
  target: '',
  bonusTarget: '',
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

Recipe? _foldedRecipe(Map<String, Recipe> recipes, String name) {
  final foldedName = _fold(name);
  for (final entry in recipes.entries) {
    if (_fold(entry.key) == foldedName) return entry.value;
  }
  return null;
}

Recipe _recipe(
  String name,
  String type,
  String method, {
  RecipeRole role = RecipeRole.production,
}) => Recipe(
  name: name,
  type: type,
  baseOutput: 1,
  group: null,
  method: method,
  ingredients: <Ingredient>[
    Ingredient(
      name: 'Input',
      quantity: 1,
      options: const <String>[],
      substituteGroup: null,
      substituteRatios: const <String, double>{},
    ),
  ],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
  role: role,
);

String _fold(String value) => value.trim().toLowerCase();
