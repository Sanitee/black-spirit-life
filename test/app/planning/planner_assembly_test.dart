import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/item_acquisition_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/source_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/editor/editor_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assembly = PlannerAssembly();

  test('merges edits, metadata, alternatives, and hidden items', () {
    final catalog = _catalog({
      'Base': _recipe('Base', 'gathered'),
      'Old': _recipe('Old', 'gathered'),
    });
    final state = _modeState(
      recipeEdits: {
        'Old': null,
        'Potion': RecipeState(
          type: 'alchemy',
          baseOutput: 1,
          ingredients: [IngredientState(name: 'Base', quantity: 2)],
        ),
      },
      ingredientMeta: {
        'Base': IngredientMetadata(category: 'Herbs', marketId: '9001'),
      },
      hiddenItems: const ['Potion'],
    );

    final result = assembly.assembleRecipes(
      catalog: catalog,
      state: state,
      supportingData: const {
        'qualityIngredients': ['Base'],
        'qualityConversions': {
          'Base': {
            'high': {'name': 'Fine Base', 'ratio': 3},
          },
        },
      },
      mode: CraftMode.alchemy,
    );

    expect(result, isNot(contains('Old')));
    expect(result, isNot(contains('Potion')));
    expect(result['Base']!.group, 'Herbs');
    expect(result['Base']!.marketId, '9001');
    expect(result['Fine Base']!.qualityBase, 'Base');
    expect(result['Special Base']!.qualityGrade, 'special');
  });

  test('explicit recipe tombstones take precedence over stale metadata', () {
    final catalog = _catalog({
      'Alchemy Stone Shard': _recipe('Alchemy Stone Shard', 'gathered'),
      'Base': _recipe('Base', 'gathered'),
    });
    final state = _modeState(
      recipeEdits: const <String, RecipeState?>{
        '  aLcHeMy StOnE sHaRd  ': null,
        'Metadata-only deleted recipe': null,
      },
      ingredientMeta: <String, IngredientMetadata>{
        'Alchemy Stone Shard': IngredientMetadata(
          category: 'Alchemy Materials',
          sourceNote: 'Stale metadata must not restore this bundled item.',
        ),
        ' metadata-ONLY DELETED recipe ': IngredientMetadata(
          category: 'Base Items',
          sourceNote: 'Stale metadata must not recreate this custom item.',
        ),
        'Base': IngredientMetadata(category: 'Gatherables'),
      },
    );

    final result = assembly.assembleRecipes(
      catalog: catalog,
      state: state,
      supportingData: const <String, Object?>{},
      mode: CraftMode.alchemy,
    );

    expect(
      result.keys.map((name) => name.trim().toLowerCase()),
      isNot(contains('alchemy stone shard')),
    );
    expect(
      result.keys.map((name) => name.trim().toLowerCase()),
      isNot(contains('metadata-only deleted recipe')),
    );
    expect(result['Base']?.group, 'Gatherables');
  });

  test('editor round-trip preserves reference-only roles while custom recipes '
      'remain production', () {
    final bundledSalvage = _recipe(
      'Recovered Material',
      'processing',
      ingredients: <Ingredient>[
        Ingredient(
          name: 'Expensive Finished Item',
          quantity: 1,
          options: const <String>[],
          substituteGroup: null,
          substituteRatios: const <String, double>{},
        ),
      ],
      role: RecipeRole.salvage,
    );
    final catalog = _catalog(<String, Recipe>{
      bundledSalvage.name: bundledSalvage,
      'Manual Material': _recipe(
        'Manual Material',
        'processing',
        ingredients: <Ingredient>[
          Ingredient(
            name: 'Chosen Finished Item',
            quantity: 1,
            options: const <String>[],
            substituteGroup: null,
            substituteRatios: const <String, double>{},
          ),
        ],
        role: RecipeRole.manualConversion,
      ),
      'Expensive Finished Item': _recipe('Expensive Finished Item', 'gathered'),
      'Chosen Finished Item': _recipe('Chosen Finished Item', 'gathered'),
    }, mode: CraftMode.processing);
    final bundledManual = catalog.items['Manual Material']!;
    final state = _modeState(
      recipeEdits: <String, RecipeState?>{
        ' recovered MATERIAL ': stateFromRecipe(bundledSalvage),
        ' manual MATERIAL ': stateFromRecipe(
          bundledManual,
        ).copyWith(role: RecipeRole.production),
        'Renamed Manual Material': stateFromRecipe(bundledManual),
        'Custom Production': RecipeState(
          type: 'processing',
          baseOutput: 1,
          ingredients: <IngredientState>[
            IngredientState(name: 'Raw Input', quantity: 1),
          ],
        ),
      },
    );

    final result = assembly.assembleRecipes(
      catalog: catalog,
      state: state,
      supportingData: const <String, Object?>{},
      mode: CraftMode.processing,
    );
    final recovered = result.entries
        .singleWhere(
          (entry) => entry.key.trim().toLowerCase() == 'recovered material',
        )
        .value;

    expect(recovered.role, RecipeRole.salvage);
    expect(recovered.isCraftable, isFalse);
    expect(
      result.entries
          .singleWhere(
            (entry) => entry.key.trim().toLowerCase() == 'manual material',
          )
          .value
          .role,
      RecipeRole.manualConversion,
    );
    expect(
      result['Renamed Manual Material']?.role,
      RecipeRole.manualConversion,
    );
    expect(result['Renamed Manual Material']?.isCraftable, isFalse);
    expect(result['Custom Production']?.role, RecipeRole.production);
    expect(result['Custom Production']?.isCraftable, isTrue);
  });

  test('maps stored mode state and supporting rules into a plan', () {
    final modeCatalog = _catalog({
      'Potion': _recipe(
        'Potion',
        'alchemy',
        ingredients: [
          Ingredient(
            name: 'Base',
            quantity: 2,
            options: const [],
            substituteGroup: null,
            substituteRatios: const {},
          ),
        ],
      ),
      'Base': _recipe('Base', 'gathered'),
    });
    final snapshot = CatalogSnapshot(
      sourceSha256: 'fixture',
      sourceByteCount: 1,
      alchemy: modeCatalog,
      cooking: _catalog(const {}, mode: CraftMode.cooking),
      processing: _catalog(const {}, mode: CraftMode.processing),
      supportingData: const {
        'marketIds': {'Base': 1001},
      },
      collisions: const [],
    );
    final state = _modeState(
      target: 'Potion',
      want: 3,
      market: MarketState(
        prices: const {'Base': 100},
        stock: const {'Base': 10},
      ),
    );

    final result = assembly.build(
      catalog: snapshot,
      mode: CraftMode.alchemy,
      state: state,
    );

    expect(result.target, 'Potion');
    expect(result.steps.single.count, 3);
    expect(result.missing.single.name, 'Base');
    expect(result.missing.single.market.total, 600);
  });

  test('parses vendorInfo and keeps custom, bundled, vendor precedence', () {
    final catalog = _catalog({
      'Base': _recipe(
        'Base',
        'gathered',
        vendor: 'Bundled Vendor',
        location: 'Bundled Location',
        npcPrice: 500,
      ),
      'Alias Base': _recipe('Alias Base', 'gathered'),
    });
    final supporting = <String, Object?>{
      'marketNameAliases': <String, Object?>{'Alias Base': 'Base'},
      'vendorInfo': <String, Object?>{
        'Base': <String, Object?>{
          'vendor': 'Vendor Fallback',
          'role': 'Material Vendor',
          'location': 'Calpheon',
          'price': 700,
        },
      },
    };
    final state = _modeState(
      ingredientMeta: <String, IngredientMetadata>{
        'Base': IngredientMetadata(
          vendor: 'Custom Vendor',
          location: 'Custom Location',
          npcPrice: 900,
        ),
      },
    );
    final recipes = assembly.assembleRecipes(
      catalog: catalog,
      state: state,
      supportingData: supporting,
      mode: CraftMode.alchemy,
    );
    final rules = assembly.plannerRules(supporting);

    final custom = resolveSourceInfo(
      name: 'Base',
      recipe: recipes['Base'],
      rules: rules,
    );
    expect(custom.vendor, 'Custom Vendor');
    expect(custom.location, 'Custom Location');
    expect(custom.npcPrice, 900);
    expect(custom.role, 'Material Vendor');

    final alias = resolveSourceInfo(
      name: 'Alias Base',
      recipe: recipes['Alias Base'],
      rules: rules,
    );
    expect(alias.vendor, 'Vendor Fallback');
    expect(alias.location, 'Calpheon');
    expect(alias.npcPrice, 700);
  });

  test('parses reviewed acquisition routes and suppresses expired ones', () {
    final rules = assembly.plannerRules(<String, Object?>{
      'marketNameAliases': <String, Object?>{
        'Ooze Alias': "Sea Monster's Ooze",
      },
      'acquisitionInfo': <String, Object?>{
        "Sea Monster's Ooze": <String, Object?>{
          'canonicalName': "Sea Monster's Ooze",
          'itemId': 45507,
          'status': 'reviewed',
          'reviewedAt': '2026-07-24',
          'routes': <Object?>[
            <String, Object?>{
              'kind': 'monster_drop',
              'summary': 'Defeat sea monsters.',
              'availability': 'permanent',
              'confidence': 'high',
            },
            <String, Object?>{
              'kind': 'event',
              'summary': 'Expired event reward.',
              'availability': 'expired',
              'confidence': 'high',
            },
          ],
        },
        'Draft Route': <String, Object?>{
          'canonicalName': 'Draft Route',
          'routes': <Object?>[
            <String, Object?>{
              'kind': 'other',
              'summary': 'This unreviewed route must stay hidden.',
              'availability': 'permanent',
              'confidence': 'high',
            },
          ],
        },
      },
    });

    final resolved = resolveItemAcquisition(name: 'ooze alias', rules: rules);
    final draft = resolveItemAcquisition(name: 'draft route', rules: rules);

    expect(resolved?.itemId, 45507);
    expect(resolved?.status, 'reviewed');
    expect(resolved?.displayableSummaries, <String>['Defeat sea monsters.']);
    expect(draft?.status, 'draft');
    expect(draft?.displayableSummaries, isEmpty);
  });

  test('parses immutable ID-backed weights without inventing fallbacks', () {
    final rules = assembly.plannerRules(<String, Object?>{
      'itemWeightIds': <String, Object?>{
        'Beer': '9213',
        'Invalid Weight': '9999',
      },
      'itemWeightsLtById': <String, Object?>{
        '9213': 0.1,
        '4680': 0.5,
        '9999': 0,
      },
    });

    expect(rules.itemWeightLtFor('Beer'), 0.1);
    expect(rules.itemWeightLtFor(' beer '), 0.1);
    expect(rules.itemWeightLtFor('Custom Plank', itemId: '4680'), 0.5);
    expect(rules.itemWeightLtFor('Invalid Weight'), isNull);
    expect(rules.itemWeightLtFor('Unknown Item'), isNull);
    expect(() => rules.itemWeightIds['Beer'] = '1', throwsUnsupportedError);
    expect(() => rules.itemWeightsLtById['9213'] = 1, throwsUnsupportedError);
  });

  test('production rules preserve the current grilled bird special value', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );

    final special = assembly
        .plannerRules(catalog.supportingData)
        .cookingSpecialMap['Grilled Bird Meat'];

    expect(special?.name, 'Steaming Hot Grilled Bird Meat');
    expect(special?.ratio, 6);
  });

  test('production Harmony closure hydrates blood groups like Avalonia', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final state = ModeState(
      target: 'Harmony Draught - Edania',
      bonusTarget: '',
      market: MarketState(),
      appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
    );

    final result = assembly.build(
      catalog: catalog,
      mode: CraftMode.alchemy,
      state: state,
    );
    final recipes = assembly.assembleRecipes(
      catalog: catalog.alchemy,
      state: state,
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: CraftMode.alchemy,
    );
    final clownBlood = recipes["Clown's Blood"]!.ingredients.firstWhere(
      (ingredient) => ingredient.name == 'Wolf Blood',
    );

    expect(result.steps, hasLength(42));
    expect(result.missing, hasLength(47));
    expect(clownBlood.substituteGroup, 'Blood Group 1');
    expect(clownBlood.options, <String>[
      'Wolf Blood',
      'Flamingo Blood',
      'Rhino Blood',
      'Cheetah Dragon Blood',
    ]);
    expect(clownBlood.substituteRatios, <String, double>{
      'Wolf Blood': 1,
      'Flamingo Blood': 0.5,
      'Rhino Blood': 1,
      'Cheetah Dragon Blood': 0.5,
    });

    Ingredient ingredient(String recipeName, String ingredientName) =>
        recipes[recipeName]!.ingredients.firstWhere(
          (ingredient) => ingredient.name == ingredientName,
        );

    final resistance = ingredient('Elixir of Resistance', 'Wolf Blood');
    expect(
      resistance.substituteRatios['Flamingo Blood'],
      closeTo(4 / 7, 0.0000001),
    );
    final antidote = ingredient('Antidote Elixir', 'Deer Blood');
    expect(antidote.substituteRatios['Pig Blood'], 2);

    final energy = ingredient('Elixir of Energy', 'Fox Blood');
    expect(energy.options, contains('Monkey Blood'));
    expect(energy.substituteRatios['Weasel Blood'], 0.5);
    expect(energy.substituteRatios['Scorpion Blood'], 1);

    final wings = ingredient('Elixir of Wings', 'Troll Blood');
    expect(wings.options, contains('Dinosaur Blood'));
    expect(wings.options, contains('Tiger Blood'));
    expect(wings.substituteRatios['Bear Blood'], 2);
    expect(wings.substituteRatios['Tiger Blood'], 2);
    expect(wings.substituteRatios['Dinosaur Blood'], 1);

    final burnRemoval = ingredient('Elixir of Burn Removal', 'Apple');
    expect(burnRemoval.quantity, 2);
    expect(burnRemoval.substituteRatios['Apple'], 1);
    expect(burnRemoval.substituteRatios['Strawberry'], 0.5);

    final selectedResistance = assembly.engine.previewIngredientSelection(
      recipes: recipes,
      state: assembly.plannerState(
        ModeState(
          target: 'Elixir of Resistance',
          bonusTarget: '',
          substituteChoices: const <String, String>{
            'recipe:Elixir of Resistance:BDO group 16': 'Flamingo Blood',
          },
          market: MarketState(),
          appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
        ),
      ),
      parentName: 'Elixir of Resistance',
      ingredient: resistance,
      rules: assembly.plannerRules(catalog.supportingData),
    );
    expect(selectedResistance.name, 'Flamingo Blood');
    expect(selectedResistance.need, 4);
  });

  test('production catalog keeps the exact newer alchemy formulas', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final recipes = catalog.alchemy.items;

    final sharpDetection = recipes['Elixir of Sharp Detection']!;
    expect(sharpDetection.marketId, '699');
    expect(sharpDetection.outputMinimum, 25);
    expect(sharpDetection.outputMaximum, 35);
    expect(
      <String, double>{
        for (final ingredient in sharpDetection.ingredients)
          ingredient.name: ingredient.quantity,
      },
      <String, double>{
        'Oil of Storms': 1,
        'Pure Powder Reagent': 6,
        'White Truffle Mushroom': 3,
        'Trace of Nature': 3,
        'Old Tree Bark': 2,
      },
    );

    final tenacious = recipes['Tenacious Origin of Life']!;
    expect(tenacious.marketId, '5303');
    expect(tenacious.outputMinimum, 1);
    expect(tenacious.outputMaximum, 3);
    expect(tenacious.defaultVariantId, 'normal-herbs');
    expect(tenacious.variants.map((variant) => variant.id), <String>[
      'normal-herbs',
      'high-quality-herbs',
      'special-herbs',
    ]);
    expect(
      tenacious.variants
          .map((variant) => variant.ingredients.first.quantity)
          .toList(growable: false),
      <double>[50, 17, 8],
    );

    final flawless = recipes['Flawless Spirit Stone']!;
    expect(flawless.marketId, '5305');
    expect(
      <String, double>{
        for (final ingredient in flawless.ingredients)
          ingredient.name: ingredient.quantity,
      },
      <String, double>{
        'Oil of Tranquility': 10,
        'Tenacious Origin of Life': 4,
        'Rough Opulent Crystal': 4,
      },
    );

    expect(recipes['Pile of Sunrise Herbs']?.marketId, '5421');
    expect(catalog.alchemy.metadata['substituteWorthGroups'], isNotNull);

    final assembled = assembly.assembleRecipes(
      catalog: catalog.alchemy,
      state: _modeState(target: 'Tenacious Origin of Life'),
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: CraftMode.alchemy,
    );
    final assembledTenacious = assembled['Tenacious Origin of Life']!;
    for (final variant in assembledTenacious.variants) {
      for (final ingredient in variant.ingredients) {
        expect(
          ingredient.options,
          isEmpty,
          reason: '${variant.id} must remain an exact all-one-quality recipe',
        );
        expect(
          ingredient.substituteRatios,
          isEmpty,
          reason: '${variant.id} must not gain mixed-quality Worth ratios',
        );
      }
    }
  });

  test('production processing variant choice reaches the assembled plan', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final state = ModeState(
      target: 'Adhesive for Upgrade',
      want: 1,
      bonusTarget: '',
      recipeVariantChoices: const <String, String>{
        'Adhesive for Upgrade': 'mixed-saps',
      },
      market: MarketState(),
      appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
    );

    final recipes = assembly.assembleRecipes(
      catalog: catalog.processing,
      state: state,
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: CraftMode.processing,
    );
    final result = assembly.build(
      catalog: catalog,
      mode: CraftMode.processing,
      state: state,
    );
    final target = result.steps.firstWhere(
      (step) => step.name == 'Adhesive for Upgrade',
    );

    expect(recipes['Adhesive for Upgrade']?.variants, hasLength(2));
    expect(target.ingredients.map((ingredient) => ingredient.name), <String>[
      'White Cedar Sap',
      'Acacia Sap',
      'Elder Tree Sap',
      "Sea Monster's Ooze",
    ]);
  });

  test(
    'every production variant ingredient resolves in the assembled catalog',
    () {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final recipes = assembly.assembleRecipes(
        catalog: catalog.processing,
        state: ModeState(
          target: '',
          bonusTarget: '',
          market: MarketState(),
          appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
        ),
        supportingData: catalog.supportingData,
        sharedMetadata: catalog.alchemy.metadata,
        mode: CraftMode.processing,
      );
      final assembledNames = {
        for (final name in recipes.keys) name.trim().toLowerCase(),
      };
      final unresolved = <String>[];

      for (final recipe in catalog.processing.items.values.where(
        (candidate) => candidate.isCraftable && candidate.hasRecipeVariants,
      )) {
        for (final variant in recipe.variants) {
          for (final ingredient in variant.ingredients) {
            if (!assembledNames.contains(
              ingredient.name.trim().toLowerCase(),
            )) {
              unresolved.add(
                '${recipe.name}/${variant.id}: ${ingredient.name}',
              );
            }
          }
        }
      }

      expect(unresolved, isEmpty);
    },
  );
}

ModeCatalog _catalog(
  Map<String, Recipe> items, {
  CraftMode mode = CraftMode.alchemy,
}) => ModeCatalog(
  mode: mode,
  items: items,
  iconDataUris: const {},
  defaults: const {},
  metadata: const {},
  searchAliases: const {},
);

Recipe _recipe(
  String name,
  String type, {
  List<Ingredient> ingredients = const [],
  String? sourceNote,
  String? vendor,
  String? location,
  double npcPrice = 0,
  RecipeRole role = RecipeRole.production,
}) => Recipe(
  name: name,
  type: type,
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: ingredients,
  marketId: null,
  sourceNote: sourceNote,
  vendor: vendor,
  location: location,
  npcPrice: npcPrice,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
  role: role,
);

ModeState _modeState({
  String target = 'Potion',
  int want = 100,
  Map<String, RecipeState?> recipeEdits = const {},
  Map<String, IngredientMetadata> ingredientMeta = const {},
  Iterable<String> hiddenItems = const [],
  MarketState? market,
}) => ModeState(
  target: target,
  want: want,
  bonusTarget: target,
  recipeEdits: recipeEdits,
  ingredientMeta: ingredientMeta,
  hiddenItems: hiddenItems,
  market: market ?? MarketState(),
  appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
);
