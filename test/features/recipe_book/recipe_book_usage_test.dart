import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'indexes required ingredients and selectable options but not ratio-only names',
    () {
      final index = _buildIndex(
        recipesByMode: <CraftMode, Map<String, Recipe>>{
          CraftMode.alchemy: <String, Recipe>{
            'Option Tonic': _recipe(
              'Option Tonic',
              mode: CraftMode.alchemy,
              ingredients: <Ingredient>[
                _ingredient('Required Herb'),
                _ingredient(
                  'Wild Grass',
                  options: const <String>['Wild Grass', 'Weed'],
                  substituteRatios: const <String, double>{
                    'Wild Grass': 1,
                    'Weed': 5,
                    'Ratio Metadata Only': 7,
                  },
                ),
              ],
            ),
            'Weed': _recipe(
              'Weed',
              mode: CraftMode.alchemy,
              ingredients: const <Ingredient>[],
            ),
          },
        },
      );

      final required = _singleEntry(index, ' required herb ');
      expect(required.name, 'Option Tonic');
      expect(_matchLabels(required.routes.single), <String>[
        'requiredIngredient:Required Herb',
      ]);

      final substitute = _singleEntry(index, 'WEED');
      expect(substitute.name, 'Option Tonic');
      expect(_matchLabels(substitute.routes.single), <String>[
        'substitute:Wild Grass',
      ]);
      final weedMatch = substitute.routes.single.matches.single;
      expect(weedMatch.sourceName, 'Weed');
      expect(weedMatch.selectedIngredientName, 'Weed');
      expect(weedMatch.originalQuantity, 1);
      expect(weedMatch.sourceQuantity, 5);
      expect(weedMatch.substituteRatio, 5);
      expect(weedMatch.qualityRatio, 1);
      expect(weedMatch.grade, 'normal');

      expect(
        index
            .snapshotFor('Ratio Metadata Only', currentMode: CraftMode.alchemy)
            .entries,
        isEmpty,
        reason:
            'A substitute ratio is metadata for an accepted option, not an '
            'independent selectable ingredient.',
      );
    },
  );

  test(
    'expands high special blue and cooking quality mappings outside Processing',
    () {
      final rules = PlannerRules(
        qualityIngredients: const <String>{'Silver Azalea'},
        qualityConversions: const <String, QualityConversionRule>{
          'Sunflower': QualityConversionRule(
            high: QualityTierRule(name: 'High-Quality Sunflower', ratio: 3),
            special: QualityTierRule(name: 'Special Sunflower', ratio: 5),
          ),
        },
        blueElixirMap: const <String, String>{'Base Elixir': 'Blue Elixir'},
        cookingSpecialMap: const <String, SpecialQualityRule>{
          'Meal Base': SpecialQualityRule(name: 'Special Meal', ratio: 2),
        },
      );
      final index = _buildIndex(
        rules: rules,
        recipesByMode: <CraftMode, Map<String, Recipe>>{
          CraftMode.alchemy: <String, Recipe>{
            'Alchemy Brew': _recipe(
              'Alchemy Brew',
              mode: CraftMode.alchemy,
              ingredients: <Ingredient>[
                _ingredient('Sunflower', quantity: 7),
                _ingredient('Base Elixir'),
                _ingredient('Silver Azalea', quantity: 8),
                _ingredient('Arrow Mushroom', quantity: 11),
              ],
            ),
            'Mirrored Processing Formula': _recipe(
              'Mirrored Processing Formula',
              mode: CraftMode.processing,
              ingredients: <Ingredient>[_ingredient('Sunflower')],
            ),
          },
          CraftMode.cooking: <String, Recipe>{
            'Cooking Dish': _recipe(
              'Cooking Dish',
              mode: CraftMode.cooking,
              ingredients: <Ingredient>[
                _ingredient('Meal Base'),
                _ingredient('Oatmeal', quantity: 5),
              ],
            ),
          },
          CraftMode.processing: <String, Recipe>{
            'Processing Product': _recipe(
              'Processing Product',
              mode: CraftMode.processing,
              ingredients: <Ingredient>[
                _ingredient('Sunflower'),
                _ingredient('Base Elixir'),
                _ingredient('Meal Base'),
              ],
            ),
            'Simple Alchemy Record': _recipe(
              'Simple Alchemy Record',
              mode: CraftMode.alchemy,
              ingredients: <Ingredient>[_ingredient('Base Elixir')],
            ),
          },
        },
      );

      for (final alternate in const <String>[
        'High-Quality Sunflower',
        'Special Sunflower',
      ]) {
        final entry = _singleEntry(index, alternate);
        expect(entry.mode, CraftMode.alchemy);
        expect(entry.name, 'Alchemy Brew');
        expect(_matchLabels(entry.routes.single), <String>[
          'qualitySubstitute:Sunflower',
        ]);
      }
      expect(
        _singleEntry(
          index,
          'High-Quality Sunflower',
        ).routes.single.matches.single.sourceQuantity,
        3,
      );
      expect(
        _singleEntry(
          index,
          'Special Sunflower',
        ).routes.single.matches.single.sourceQuantity,
        2,
      );

      final blue = index
          .snapshotFor('Blue Elixir', currentMode: CraftMode.alchemy)
          .entries
          .singleWhere((entry) => entry.name == 'Alchemy Brew');
      expect(blue.mode, CraftMode.alchemy);
      expect(blue.name, 'Alchemy Brew');
      expect(_matchLabels(blue.routes.single), <String>[
        'qualitySubstitute:Base Elixir',
      ]);
      expect(
        index
            .snapshotFor('Blue Elixir', currentMode: CraftMode.processing)
            .entries
            .where((entry) => entry.name == 'Simple Alchemy Record')
            .single
            .mode,
        CraftMode.processing,
        reason:
            'Quality behavior follows the effective formula type, not the '
            'catalog tab that contains it.',
      );

      final cooking = _singleEntry(
        index,
        'Special Meal',
        currentMode: CraftMode.cooking,
      );
      expect(cooking.mode, CraftMode.cooking);
      expect(cooking.name, 'Cooking Dish');
      expect(_matchLabels(cooking.routes.single), <String>[
        'qualitySubstitute:Meal Base',
      ]);
      final oatmeal = _singleEntry(
        index,
        'Refined Oatmeal',
        currentMode: CraftMode.cooking,
      );
      expect(oatmeal.name, 'Cooking Dish');
      expect(oatmeal.routes.single.matches.single.sourceQuantity, 3);
      expect(oatmeal.routes.single.matches.single.grade, 'blue');

      for (final alternate in const <String>[
        'High-Quality Silver Azalea',
        'Special Silver Azalea',
        'High-Quality Arrow Mushroom',
        'Special Arrow Mushroom',
      ]) {
        final entry = _singleEntry(index, alternate);
        expect(entry.name, 'Alchemy Brew');
        expect(
          entry.routes.single.matches.single.kind,
          RecipeBookUseKind.qualitySubstitute,
        );
      }

      for (final alternate in const <String>[
        'High-Quality Sunflower',
        'Special Sunflower',
        'Blue Elixir',
        'Special Meal',
      ]) {
        expect(
          index
              .snapshotFor(alternate, currentMode: CraftMode.processing)
              .entries
              .where(
                (entry) =>
                    entry.name == 'Processing Product' ||
                    entry.name == 'Mirrored Processing Formula',
              ),
          isEmpty,
          reason:
              'Processing recipes must not advertise planner quality '
              'substitutions for $alternate.',
        );
      }
    },
  );

  test('variant formulas are authoritative and never duplicate the base', () {
    final recipe = _recipe(
      'Variant Product',
      mode: CraftMode.alchemy,
      ingredients: <Ingredient>[
        _ingredient('Legacy Base Ingredient'),
        _ingredient('Shared Ingredient'),
      ],
      variants: <RecipeVariant>[
        _variant(
          id: 'route-a',
          label: 'Route A',
          routeId: 'route-a',
          mode: CraftMode.alchemy,
          ingredients: <Ingredient>[_ingredient('Shared Ingredient')],
        ),
        _variant(
          id: 'route-b',
          label: 'Route B',
          routeId: 'route-b',
          mode: CraftMode.alchemy,
          ingredients: <Ingredient>[_ingredient('Route B Ingredient')],
        ),
      ],
      defaultVariantId: 'route-a',
    );
    final index = _buildIndex(
      recipesByMode: <CraftMode, Map<String, Recipe>>{
        CraftMode.alchemy: <String, Recipe>{recipe.name: recipe},
      },
    );

    expect(
      index
          .snapshotFor('Legacy Base Ingredient', currentMode: CraftMode.alchemy)
          .entries,
      isEmpty,
      reason:
          'Once complete variants exist, the legacy/base formula is not a '
          'second usable route.',
    );

    final shared = _singleEntry(index, 'Shared Ingredient');
    expect(shared.routes.map((route) => route.id), <String>['route-a']);
    expect(shared.routes.single.variantId, 'route-a');
    expect(shared.routes.single.routeId, 'route-a');

    final routeB = _singleEntry(index, 'Route B Ingredient');
    expect(routeB.routes.map((route) => route.id), <String>['route-b']);
  });

  test('preserves and deduplicates 10x and 100x routes for one output', () {
    final recipe = _recipe(
      'Bulk Product',
      mode: CraftMode.processing,
      ingredients: <Ingredient>[_ingredient('Legacy Raw')],
      variants: <RecipeVariant>[
        _variant(
          id: 'standard',
          label: 'Standard',
          routeId: 'standard',
          batchMultiplier: 1,
          mode: CraftMode.processing,
          ingredients: <Ingredient>[_ingredient('Single Raw')],
        ),
        _variant(
          id: 'standard-10x',
          label: 'Standard',
          routeId: 'standard',
          batchMultiplier: 10,
          mode: CraftMode.processing,
          ingredients: <Ingredient>[
            _ingredient('Single Raw', quantity: 10),
            _ingredient('Batch Catalyst'),
          ],
        ),
        _variant(
          id: 'standard-100x',
          label: 'Standard',
          routeId: 'standard',
          batchMultiplier: 100,
          mode: CraftMode.processing,
          ingredients: <Ingredient>[
            _ingredient('Single Raw', quantity: 100),
            _ingredient('Batch Catalyst'),
            _ingredient('Batch Catalyst', quantity: 2),
          ],
        ),
      ],
      defaultVariantId: 'standard',
    );
    final index = _buildIndex(
      recipesByMode: <CraftMode, Map<String, Recipe>>{
        CraftMode.processing: <String, Recipe>{recipe.name: recipe},
      },
    );

    final snapshot = index.snapshotFor(
      'Batch Catalyst',
      currentMode: CraftMode.processing,
    );
    expect(snapshot.recipeCount, 1);
    final entry = snapshot.entries.single;
    expect(entry.routes.map((route) => route.id), <String>[
      'standard-10x',
      'standard-100x',
    ]);
    expect(entry.routes.map((route) => route.variantId), <String>[
      'standard-10x',
      'standard-100x',
    ]);
    expect(entry.routes.map((route) => route.routeId), <String>[
      'standard',
      'standard',
    ]);
    expect(entry.routes.map((route) => route.batchMultiplier), <int>[10, 100]);
    expect(
      entry.routes.map((route) => route.matches.length),
      <int>[1, 1],
      reason:
          'Repeated ingredient rows in one complete formula must not duplicate '
          'the route or its match.',
    );
    expect(entry.preferredVariantId('standard-100x'), 'standard-100x');
    expect(entry.preferredVariantId('not-present'), 'standard-10x');
  });

  test(
    'keeps cross-mode same-name outputs distinct and orders deterministically',
    () {
      final index = _buildIndex(
        recipesByMode: <CraftMode, Map<String, Recipe>>{
          CraftMode.processing: <String, Recipe>{
            'Zulu Processing': _consumer(
              'Zulu Processing',
              CraftMode.processing,
            ),
            'Shared Output': _consumer('Shared Output', CraftMode.processing),
          },
          CraftMode.cooking: <String, Recipe>{
            'Cooking Output': _consumer('Cooking Output', CraftMode.cooking),
          },
          CraftMode.alchemy: <String, Recipe>{
            'Zulu Alchemy': _consumer('Zulu Alchemy', CraftMode.alchemy),
            'Shared Output': _consumer('Shared Output', CraftMode.alchemy),
            'Alpha Alchemy': _consumer('Alpha Alchemy', CraftMode.alchemy),
          },
        },
      );

      final snapshot = index.snapshotFor(
        'Common Input',
        currentMode: CraftMode.processing,
      );
      expect(
        snapshot.entries.map((entry) => '${entry.mode.key}:${entry.name}'),
        <String>[
          'processing:Shared Output',
          'processing:Zulu Processing',
          'alchemy:Alpha Alchemy',
          'alchemy:Shared Output',
          'alchemy:Zulu Alchemy',
          'cooking:Cooking Output',
        ],
      );
      expect(
        snapshot.entries
            .where((entry) => entry.name == 'Shared Output')
            .map((entry) => entry.mode),
        <CraftMode>[CraftMode.processing, CraftMode.alchemy],
      );
      expect(snapshot.modeCounts, <CraftMode, int>{
        CraftMode.alchemy: 3,
        CraftMode.cooking: 1,
        CraftMode.processing: 2,
      });

      expect(
        index
            .snapshotFor('Common Input', currentMode: CraftMode.processing)
            .entries
            .map((entry) => '${entry.mode.key}:${entry.name}'),
        snapshot.entries.map((entry) => '${entry.mode.key}:${entry.name}'),
      );
    },
  );

  test(
    'excludes self references and noncraftable manual and salvage recipes',
    () {
      final index = _buildIndex(
        recipesByMode: <CraftMode, Map<String, Recipe>>{
          CraftMode.alchemy: <String, Recipe>{
            'Common Input': _recipe(
              'Common Input',
              mode: CraftMode.alchemy,
              ingredients: <Ingredient>[_ingredient('Common Input')],
            ),
            'Valid Output': _consumer('Valid Output', CraftMode.alchemy),
            'Assorted Side Dishes': _consumer(
              'Assorted Side Dishes',
              CraftMode.alchemy,
            ),
            'Manual Output': _recipe(
              'Manual Output',
              mode: CraftMode.alchemy,
              role: RecipeRole.manualConversion,
              ingredients: <Ingredient>[_ingredient('Common Input')],
            ),
            'Salvage Output': _recipe(
              'Salvage Output',
              mode: CraftMode.alchemy,
              role: RecipeRole.salvage,
              ingredients: <Ingredient>[_ingredient('Common Input')],
            ),
          },
        },
      );

      expect(
        index
            .snapshotFor('Common Input', currentMode: CraftMode.alchemy)
            .entries
            .map((entry) => entry.name),
        <String>['Valid Output'],
      );
    },
  );

  test('production catalog keeps real bulk routes and output bounds', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final index = RecipeBookUsageIndex.build(
      recipesByMode: <CraftMode, Map<String, Recipe>>{
        for (final mode in CraftMode.values) mode: catalog.forMode(mode).items,
      },
      rules: const PlannerAssembly().plannerRules(catalog.supportingData),
    );

    final purePowder = index.snapshotFor(
      'Pure Powder Reagent',
      currentMode: CraftMode.processing,
    );
    for (final output in const <String>['Black Gem', 'Caphras Stone']) {
      final entry = purePowder.entries.singleWhere(
        (candidate) =>
            candidate.mode == CraftMode.processing && candidate.name == output,
      );
      expect(entry.routes.map((route) => route.batchMultiplier), contains(100));
    }

    final blackStonePowder = index.snapshotFor(
      'Black Stone Powder',
      currentMode: CraftMode.processing,
    );
    final magicalShard = blackStonePowder.entries.singleWhere(
      (entry) =>
          entry.mode == CraftMode.processing && entry.name == 'Magical Shard',
    );
    final bulk = magicalShard.routes.singleWhere(
      (route) => route.batchMultiplier == 10,
    );
    expect(bulk.variantId, 'standard-10x');
    expect(bulk.outputMinimum, 10);
    expect(bulk.outputMaximum, 10);
  });
}

RecipeBookUsageIndex _buildIndex({
  required Map<CraftMode, Map<String, Recipe>> recipesByMode,
  PlannerRules? rules,
}) => RecipeBookUsageIndex.build(
  recipesByMode: recipesByMode,
  rules: rules ?? PlannerRules(),
);

RecipeBookUseEntry _singleEntry(
  RecipeBookUsageIndex index,
  String itemName, {
  CraftMode currentMode = CraftMode.alchemy,
}) => index.snapshotFor(itemName, currentMode: currentMode).entries.single;

List<String> _matchLabels(RecipeBookUseRoute route) => route.matches
    .map((match) => '${match.kind.name}:${match.ingredientName}')
    .toList(growable: false);

Recipe _consumer(String name, CraftMode mode) => _recipe(
  name,
  mode: mode,
  ingredients: <Ingredient>[_ingredient('Common Input')],
);

Recipe _recipe(
  String name, {
  required CraftMode mode,
  required List<Ingredient> ingredients,
  RecipeRole role = RecipeRole.production,
  List<RecipeVariant> variants = const <RecipeVariant>[],
  String? defaultVariantId,
}) => Recipe(
  name: name,
  type: mode.key,
  baseOutput: 1,
  group: 'Synthetic',
  method: mode == CraftMode.processing ? 'Heating' : null,
  ingredients: ingredients,
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
  variants: variants,
  defaultVariantId: defaultVariantId,
);

RecipeVariant _variant({
  required String id,
  required String label,
  required String routeId,
  required CraftMode mode,
  required List<Ingredient> ingredients,
  int batchMultiplier = 1,
}) => RecipeVariant(
  id: id,
  label: label,
  routeId: routeId,
  batchMultiplier: batchMultiplier,
  type: mode.key,
  baseOutput: batchMultiplier.toDouble(),
  method: mode == CraftMode.processing ? 'Heating' : null,
  ingredients: ingredients,
  outputMinimum: batchMultiplier.toDouble(),
  outputMaximum: batchMultiplier.toDouble(),
);

Ingredient _ingredient(
  String name, {
  double quantity = 1,
  List<String> options = const <String>[],
  Map<String, double> substituteRatios = const <String, double>{},
}) => Ingredient(
  name: name,
  quantity: quantity,
  options: options,
  substituteGroup: options.isEmpty ? null : '$name group',
  substituteRatios: substituteRatios,
);
