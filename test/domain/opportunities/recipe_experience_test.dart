import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_experience.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  late Map<CraftMode, Map<String, Recipe>> assembled;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    assembled = {
      for (final mode in CraftMode.values)
        mode: const PlannerAssembly().assembleRecipes(
          catalog: catalog.forMode(mode),
          state: ModeState(
            target: '',
            bonusTarget: '',
            market: MarketState(),
            appearance: AppearanceSettings.defaultsFor(mode),
          ),
          supportingData: catalog.supportingData,
          sharedMetadata: catalog.alchemy.metadata,
          mode: mode,
          processingRecipes: catalog.processing.items,
        ),
    };
  });

  Recipe recipe(String name, CraftMode mode) =>
      catalog.forMode(mode).items[name]!;

  test('Codex primary and exact-formula BDOLytics gaps have base EXP', () {
    const cases = <CraftMode, Map<String, double>>{
      CraftMode.cooking: {'Beer': 400, 'Balenos Meal': 1600, 'Chowder': 800},
      CraftMode.alchemy: {'Metal Solvent': 800, 'Perfume of Tenacity': 2000},
      CraftMode.processing: {'Acacia Plank': 200, 'Acacia Plywood': 500},
    };
    for (final mode in cases.keys) {
      for (final entry in cases[mode]!.entries) {
        final result = experienceFor(recipe(entry.key, mode), mode)!;
        expect(result.value, entry.value, reason: entry.key);
        expect(result.estimated, isFalse, reason: entry.key);
        expect(result.skill, mode.key, reason: entry.key);
        expect(result.sourceReference, contains('https://'));
      }
    }
    expect(
      experienceFor(
        recipe('Beer', CraftMode.cooking),
        CraftMode.cooking,
      )!.sourceReference,
      contains('bdocodex.com'),
    );
    expect(
      experienceFor(
        recipe('Chowder', CraftMode.cooking),
        CraftMode.cooking,
      )!.sourceReference,
      contains('6394:4f522d67b4ba'),
    );
  });

  test('only the approved eleven comparisons are marked estimates', () {
    const cases = <CraftMode, Map<String, double>>{
      CraftMode.alchemy: {
        'Elixir of Edania': 920,
        'Perfume of Insight': 2000,
        'Perfume of Verdure': 2000,
        'Oil of Enchantment': 1400,
        'Elixir of Persistence': 1610,
        'Elixir of Brawn': 1610,
      },
      CraftMode.processing: {
        'Rice Flour': 70,
        'Snowfield Cedar Plank': 200,
        'Pure Gold Crystal': 1500,
        'Pure Platinum Crystal': 1500,
        'Pure Silver Crystal': 1500,
      },
    };
    for (final mode in cases.keys) {
      for (final entry in cases[mode]!.entries) {
        final result = experienceFor(recipe(entry.key, mode), mode)!;
        expect(result.value, entry.value, reason: entry.key);
        expect(result.estimated, isTrue, reason: entry.key);
        expect(result.sourceReference, startsWith('Estimate:'));
      }
    }
  });

  test(
    'unknown, unverified zero and removed records never become zero EXP',
    () {
      for (final name in <String>[
        'Corrupt Oil of Immortality',
        'Purified Lightstone of Fire',
        'Purified Lightstone of Earth',
        'Purified Lightstone of Wind',
        'Purified Lightstone of Flora',
        'Tenacious Origin of Life',
        'Rough Opulent Crystal',
        'Flawless Spirit Stone',
      ]) {
        expect(
          experienceFor(recipe(name, CraftMode.alchemy), CraftMode.alchemy),
          isNull,
          reason: name,
        );
      }
      for (final name in <String>['Black Stone Powder', 'Fine Soft Hide']) {
        expect(
          experienceFor(
            recipe(name, CraftMode.processing),
            CraftMode.processing,
          ),
          isNull,
          reason: name,
        );
      }
    },
  );

  test('active batch and route are guarded independently', () {
    final stone = recipe(
      'Concentrated Magical Black Stone',
      CraftMode.processing,
    );
    expect(
      experienceFor(
        stone.resolveVariant('standard'),
        CraftMode.processing,
      )!.value,
      500,
    );
    expect(
      experienceFor(stone.resolveVariant('standard-10x'), CraftMode.processing),
      isNull,
    );
    final powder = recipe('Insectivore Plant Powder', CraftMode.processing);
    expect(
      experienceFor(
        powder.resolveVariant('flowers'),
        CraftMode.processing,
      )!.value,
      1000,
    );
    expect(
      experienceFor(
        powder.resolveVariant('leaves-and-fragments'),
        CraftMode.processing,
      ),
      isNull,
    );
    final perfume = recipe('Perfume of Verdure', CraftMode.alchemy);
    expect(
      experienceFor(
        perfume.resolveVariant('alchemy-tool'),
        CraftMode.alchemy,
      )!.value,
      2000,
    );
    expect(
      experienceFor(
        perfume.resolveVariant('simple-alchemy'),
        CraftMode.alchemy,
      ),
      isNull,
    );
  });

  test('changes to audited formula or identity cannot inherit EXP', () {
    final beer = recipe('Beer', CraftMode.cooking);
    final first = beer.ingredients.first;
    Ingredient input({
      String? name,
      double? quantity,
      List<String>? options,
      String? group,
      Map<String, double>? ratios,
    }) => Ingredient(
      name: name ?? first.name,
      quantity: quantity ?? first.quantity,
      options: options ?? first.options,
      substituteGroup: group ?? first.substituteGroup,
      substituteRatios: ratios ?? first.substituteRatios,
    );
    for (final changed in <Recipe>[
      copy(beer, name: 'Custom Beer'),
      copy(beer, type: 'alchemy'),
      copy(beer, method: 'Simple Cooking'),
      copy(beer, marketId: '999999'),
      copy(beer, baseOutput: 9),
      copy(beer, outputMinimum: 20),
      copy(beer, outputMaximum: 25),
      for (final ingredient in <Ingredient>[
        input(name: 'Salt'),
        input(quantity: first.quantity + 1),
        input(options: [...first.options, 'Unknown Grain']),
        input(group: 'Another group'),
        input(ratios: {'Wheat': 999}),
      ])
        copy(beer, ingredients: [ingredient, ...beer.ingredients.skip(1)]),
      copy(beer, role: RecipeRole.manualConversion),
      copy(beer, role: RecipeRole.salvage),
    ]) {
      expect(experienceFor(changed, CraftMode.cooking), isNull);
    }
    expect(experienceFor(beer, CraftMode.alchemy), isNull);
    expect(
      experienceFor(copy(beer, ingredients: []), CraftMode.cooking),
      isNull,
    );
  });

  test('presentation metadata and row order do not invalidate a formula', () {
    final beer = recipe('Beer', CraftMode.cooking);
    final reordered = copy(
      beer,
      ingredients: beer.ingredients.reversed.toList(),
      sourceNote: 'Personal note',
      group: 'Custom display category',
    );
    expect(experienceFor(reordered, CraftMode.cooking)!.value, 400);
  });

  test('skill follows active method, not the containing tab', () {
    final beer = recipe('Beer', CraftMode.cooking);
    expect(
      experienceSkillFor(copy(beer, type: 'processing', method: 'Heating')),
      'processing',
    );
    expect(
      experienceSkillFor(
        copy(beer, type: 'processing', method: 'Simple Alchemy'),
      ),
      'alchemy',
    );
    expect(
      experienceSkillFor(
        copy(beer, type: 'processing', method: 'Simple Cooking'),
      ),
      'cooking',
    );
    expect(
      experienceSkillFor(
        copy(beer, type: 'processing', method: 'Refinery Lv. 3'),
      ),
      isNull,
    );
    expect(experienceSkillFor(copy(beer, role: RecipeRole.salvage)), isNull);
  });

  test('raw and clean assembled catalogs retain audited default coverage', () {
    const expected = <CraftMode, (int, int)>{
      CraftMode.alchemy: (79, 6),
      CraftMode.cooking: (150, 0),
      CraftMode.processing: (145, 5),
    };
    for (final mode in CraftMode.values) {
      for (final recipes in [catalog.forMode(mode).items, assembled[mode]!]) {
        var sourced = 0;
        var estimates = 0;
        for (final item in recipes.values) {
          final value = experienceFor(item, mode);
          if (value == null) continue;
          expect(
            value.value.isFinite && value.value > 0,
            isTrue,
            reason: item.name,
          );
          expect(value.skill, experienceSkillFor(item));
          if (value.estimated) {
            estimates++;
          } else {
            sourced++;
          }
        }
        expect((sourced, estimates), expected[mode], reason: mode.key);
      }
    }
  });
}

Recipe copy(
  Recipe source, {
  String? name,
  String? type,
  String? method,
  double? baseOutput,
  String? marketId,
  List<Ingredient>? ingredients,
  RecipeRole? role,
  double? outputMinimum,
  double? outputMaximum,
  String? sourceNote,
  String? group,
}) => Recipe(
  name: name ?? source.name,
  type: type ?? source.type,
  method: method ?? source.method,
  baseOutput: baseOutput ?? source.baseOutput,
  group: group ?? source.group,
  ingredients: ingredients ?? source.ingredients,
  marketId: marketId ?? source.marketId,
  sourceNote: sourceNote ?? source.sourceNote,
  vendor: source.vendor,
  location: source.location,
  npcPrice: source.npcPrice,
  qualityBase: source.qualityBase,
  qualityGrade: source.qualityGrade,
  outputMinimum: outputMinimum ?? source.outputMinimum,
  outputMaximum: outputMaximum ?? source.outputMaximum,
  role: role ?? source.role,
  variants: source.variants,
  defaultVariantId: source.defaultVariantId,
);
