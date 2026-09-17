import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_effort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('effort compares depth first, then distinct crafted branches', () {
    const shallow = RecipeEffort(depth: 1, craftedBranches: 20);
    const deep = RecipeEffort(depth: 2, craftedBranches: 1);
    const wider = RecipeEffort(depth: 2, craftedBranches: 2);
    expect(shallow.compareTo(deep), lessThan(0));
    expect(deep.compareTo(wider), lessThan(0));
    expect(deep, const RecipeEffort(depth: 2, craftedBranches: 1));
    expect(
      deep.hashCode,
      const RecipeEffort(depth: 2, craftedBranches: 1).hashCode,
    );
  });

  test('follows cross-mode elixir and draught chains above raw processing', () {
    final reagent = recipe('Reagent', ['Herb']);
    final elixir = recipe('Elixir', ['Reagent', 'Water']);
    final draught = recipe('Draught', ['Elixir']);
    final harmony = recipe('Harmony', ['Draught']);
    final flour = recipe('Flour', ['Grain']);
    final index = RecipeEffortIndex({
      CraftMode.alchemy: items([reagent, elixir]),
      CraftMode.processing: items([draught, harmony, flour]),
    });
    expect(index.effortFor(harmony, CraftMode.processing), effort(4, 3));
    expect(index.effortFor(draught, CraftMode.processing), effort(3, 2));
    expect(index.effortFor(elixir, CraftMode.alchemy), effort(2, 1));
    expect(index.effortFor(flour, CraftMode.processing), effort(1, 0));
  });

  test('uses real production across modes instead of a local raw record', () {
    final oil = recipe('Oil', ['Blood']);
    final localOil = recipe('Oil', []);
    final draught = recipe('Draught', ['Oil']);
    final index = RecipeEffortIndex({
      CraftMode.alchemy: items([oil]),
      CraftMode.processing: items([localOil, draught]),
    });
    expect(index.effortFor(draught, CraftMode.processing), effort(2, 1));
    expect(index.effortFor(localOil, CraftMode.processing), effort(0, 0));
  });

  test('breadth counts shared crafted dependencies once', () {
    final base = recipe('Base', ['Herb']);
    final a = recipe('A', ['Base']);
    final b = recipe('B', ['Base']);
    final narrow = recipe('Narrow', ['A', 'A']);
    final wide = recipe('Wide', ['A', 'B']);
    final index = indexFor([base, a, b, narrow, wide]);
    expect(index.effortFor(narrow, CraftMode.processing), effort(3, 2));
    expect(index.effortFor(wide, CraftMode.processing), effort(3, 3));
  });

  test('normalizes one ordinary batch per route, ignoring bulk catalysts', () {
    final catalyst = recipe('Catalyst', ['Intermediate']);
    final intermediate = recipe('Intermediate', ['Herb']);
    final bulk = recipe(
      'Bulk product',
      ['Raw', 'Catalyst'],
      variants: [
        variant('bulk', ['Raw', 'Catalyst'], route: 'standard', batch: 100),
        variant('single', ['Raw'], route: 'standard'),
      ],
    );
    final index = indexFor([catalyst, intermediate, bulk]);
    expect(index.effortFor(bulk, CraftMode.processing), effort(1, 0));
    expect(
      index.effortFor(bulk.resolveVariant('bulk'), CraftMode.processing),
      effort(1, 0),
    );
  });

  test(
    'chooses a simpler ordinary route and a simpler recorded substitute',
    () {
      final compound = recipe('Compound', ['Intermediate']);
      final intermediate = recipe('Intermediate', ['Raw']);
      final alternate = recipe(
        'Alternate',
        ['Compound'],
        variants: [
          variant('long', ['Compound']),
          variant('short', ['Raw']),
        ],
      );
      final substitute = recipe(
        'Substitute',
        ['Compound'],
        options: {
          'Compound': ['Raw', 'Absent option'],
        },
      );
      final index = indexFor([
        compound,
        intermediate,
        alternate,
        substitute,
        recipe('Raw', []),
      ]);
      expect(index.effortFor(alternate, CraftMode.processing), effort(1, 0));
      expect(
        index.effortFor(alternate.resolveVariant('long'), CraftMode.processing),
        effort(3, 2),
      );
      expect(
        index.effortFor(
          alternate.resolveVariant('short'),
          CraftMode.processing,
        ),
        effort(1, 0),
      );
      expect(index.effortFor(substitute, CraftMode.processing), effort(1, 0));
    },
  );

  test('an absent alternative cannot invent an easier route', () {
    final intermediate = recipe('Intermediate', ['Raw']);
    final product = recipe(
      'Product',
      ['Intermediate'],
      options: {
        'Intermediate': ['Not in the catalog'],
      },
    );
    final index = indexFor([intermediate, product]);
    expect(index.effortFor(product, CraftMode.processing), effort(2, 1));
  });

  test('skips manual, salvage, archived and unavailable production', () {
    final manual = recipe('Manual', ['Raw'], role: RecipeRole.manualConversion);
    final salvage = recipe('Salvage', ['Raw'], role: RecipeRole.salvage);
    final archived = recipe('Monkey Blood', ['Raw'], marketId: '6211');
    final legacy = recipe('Legacy', ['Raw']);
    final callback = recipe('Callback', ['Raw']);
    final ordinary = recipe('Ordinary', ['Manual', 'Salvage']);
    final index = RecipeEffortIndex(
      {
        CraftMode.processing: items([
          manual,
          salvage,
          archived,
          legacy,
          callback,
          ordinary,
        ]),
      },
      legacyUnavailableItems: ['LEGACY'],
      isUnavailable: (item, mode) => item.name == 'Callback',
    );
    for (final item in [manual, salvage, archived, legacy, callback]) {
      expect(index.effortFor(item, CraftMode.processing), effort(0, 0));
    }
    expect(index.effortFor(ordinary, CraftMode.processing), effort(1, 0));
  });

  test(
    'cyclic routes terminate without inflating effort or query-order drift',
    () {
      final a = recipe('A', ['B']);
      final b = recipe('B', ['A']);
      final self = recipe('Self', ['Self']);
      for (final order in [
        [a, b, self],
        [self, b, a],
      ]) {
        final index = indexFor(order);
        for (final item in order) {
          expect(index.effortFor(item, CraftMode.processing), effort(1, 0));
        }
        for (final item in order.reversed) {
          expect(index.effortFor(item, CraftMode.processing), effort(1, 0));
        }
      }
    },
  );

  test('a valid escape from a cyclic route has its real finite depth', () {
    final a = recipe(
      'A',
      ['B'],
      variants: [
        variant('cyclic', ['B']),
        variant('ordinary', ['Raw']),
      ],
    );
    final b = recipe('B', ['A']);
    for (final order in [
      [a, b],
      [b, a],
    ]) {
      final index = indexFor(order);
      expect(index.effortFor(b, CraftMode.processing), effort(2, 1));
      expect(index.effortFor(a, CraftMode.processing), effort(1, 0));
      expect(
        index.effortFor(a.resolveVariant('cyclic'), CraftMode.processing),
        effort(1, 0),
      );
    }
  });

  test(
    'equal-cost alternative selection is deterministic across map order',
    () {
      final left = recipe('Left', ['Raw']);
      final right = recipe('Right', ['Raw']);
      final choice = recipe(
        'Choice',
        ['Right'],
        options: {
          'Right': ['Left'],
        },
      );
      final target = recipe('Target', ['Choice', 'Left']);
      final definitions = [left, right, choice, target];
      final first = indexFor(definitions);
      final second = indexFor(definitions.reversed.toList());
      expect(first.effortFor(target, CraftMode.processing), effort(3, 2));
      expect(
        first.effortFor(target, CraftMode.processing),
        second.effortFor(target, CraftMode.processing),
      );
    },
  );

  test(
    'copies lookup ownership and caches effort for an unchanged snapshot',
    () {
      final product = recipe('Product', ['Raw']);
      final mutableItems = items([product]);
      final index = RecipeEffortIndex({CraftMode.processing: mutableItems});
      final first = index.effortFor(product, CraftMode.processing);
      mutableItems.clear();
      expect(index.effortFor(product, CraftMode.processing), same(first));
    },
  );

  test(
    'real catalog ranks Harmony chains above straightforward raw processing',
    () {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final recipes = {
        for (final mode in CraftMode.values) mode: catalog.forMode(mode).items,
      };
      final index = RecipeEffortIndex(recipes);
      RecipeEffort processing(String name) => index.effortFor(
        recipes[CraftMode.processing]![name]!,
        CraftMode.processing,
      );
      expect(
        processing('Harmony Draught').compareTo(processing('Wheat Flour')),
        greaterThan(0),
      );
      expect(
        processing(
          'Immortal: Harmony Draught',
        ).compareTo(processing('Harmony Draught')),
        greaterThan(0),
      );
      expect(processing('Wheat Flour'), effort(1, 0));
      for (final mode in CraftMode.values) {
        for (final recipe in recipes[mode]!.values) {
          final value = index.effortFor(recipe, mode);
          expect(value.depth, greaterThanOrEqualTo(0), reason: recipe.name);
          expect(value.depth, lessThanOrEqualTo(catalog.totalCraftableCount));
        }
      }
    },
  );
}

RecipeEffort effort(int depth, int branches) =>
    RecipeEffort(depth: depth, craftedBranches: branches);

RecipeEffortIndex indexFor(List<Recipe> recipes) =>
    RecipeEffortIndex({CraftMode.processing: items(recipes)});

Map<String, Recipe> items(List<Recipe> recipes) => {
  for (final recipe in recipes) recipe.name: recipe,
};

Ingredient ingredient(String name, {List<String> options = const []}) =>
    Ingredient(
      name: name,
      quantity: 1,
      options: options,
      substituteGroup: null,
      substituteRatios: const {},
    );

Recipe recipe(
  String name,
  List<String> ingredients, {
  Map<String, List<String>> options = const {},
  RecipeRole role = RecipeRole.production,
  String? marketId,
  List<RecipeVariant> variants = const [],
}) => Recipe(
  name: name,
  type: ingredients.isEmpty ? 'material' : 'processing',
  baseOutput: 1,
  group: null,
  method: 'Simple Alchemy',
  ingredients: ingredients.map(
    (name) => ingredient(name, options: options[name] ?? const []),
  ),
  marketId: marketId,
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
);

RecipeVariant variant(
  String id,
  List<String> ingredients, {
  String? route,
  int batch = 1,
}) => RecipeVariant(
  id: id,
  label: id,
  type: 'processing',
  method: 'Simple Alchemy',
  baseOutput: batch.toDouble(),
  routeId: route,
  batchMultiplier: batch,
  ingredients: ingredients.map((name) => ingredient(name)),
  outputMinimum: batch.toDouble(),
  outputMaximum: batch.toDouble(),
);
