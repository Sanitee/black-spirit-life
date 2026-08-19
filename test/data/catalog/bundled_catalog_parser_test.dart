import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('assets/data/app-data.json').readAsStringSync();
  });

  test('loads the complete approved production catalog', () {
    final catalog = const BundledCatalogParser().parse(source);

    expect(catalog.sourceByteCount, productionCatalogByteCount);
    expect(catalog.sourceSha256, productionCatalogSha256);
    expect(catalog.totalItemCount, 1627);
    expect(catalog.totalCraftableCount, 931);
    expect(catalog.totalIngredientRowCount, 2803);
    expect(catalog.collisions, hasLength(20));
    expect(catalog.alchemy.iconDataUris, hasLength(438));
    expect(catalog.cooking.iconDataUris, hasLength(612));
    expect(catalog.processing.iconDataUris, hasLength(3436));
    expect(catalog.processing.searchAliases, hasLength(160));
    expect(catalog.alchemy.defaults['target'], 'Harmony Draught');
    expect(catalog.cooking.defaults['target'], 'Beer');
    expect(
      catalog.processing.defaults['target'],
      'Blessing of Mystic Beasts - All AP',
    );
    for (final mode in CraftMode.values) {
      final defaults = catalog.forMode(mode).defaults;
      expect(defaults['inv'], isEmpty);
      expect(defaults['favoriteRecipes'], isEmpty);
    }
    final processingDefault =
        catalog.processing.items['Blessing of Mystic Beasts - All AP'];
    expect(processingDefault?.marketId, '767969');
    expect(processingDefault?.defaultVariantId, 'parchment');
    final itemWeightIds =
        catalog.supportingData['itemWeightIds'] as Map<String, Object?>;
    final itemWeightsLtById =
        catalog.supportingData['itemWeightsLtById'] as Map<String, Object?>;
    expect(itemWeightIds, hasLength(1686));
    expect(itemWeightsLtById, hasLength(1685));
    expect(itemWeightIds['Beer'], '9213');
    expect(itemWeightsLtById['9213'], 0.1);
    expect(itemWeightIds['Acacia Plank'], '4680');
    expect(itemWeightsLtById['4680'], 0.5);
    expect(itemWeightIds['Cottonseed Oil'], '9022');
    expect(itemWeightsLtById['9022'], 0.01);
    expect(
      catalog.processing.searchAliases["Ah'krad Crystal"],
      'crystal; endgame crystal; gear setup',
    );
    expect(
      catalog.processing.searchAliases.values.every(
        (terms) => terms.trim().isNotEmpty,
      ),
      isTrue,
    );
    expect(catalog.cooking.auditedCraftableCount, 172);
    expect(catalog.cooking.plannerCraftableCount, 171);
    expect(catalog.processing.plannerCraftableCount, 609);
    final endtimes =
        catalog.processing.items['Crystallized Energy of Endtimes'];
    expect(endtimes?.marketId, '821252');
    expect(endtimes?.role, RecipeRole.salvage);
    expect(endtimes?.isCraftable, isFalse);
    expect(endtimes?.outputMinimum, 100);
    expect(endtimes?.outputMaximum, 100);
    expect(endtimes?.ingredients.single.name, 'HAN Dawn Crystal - Accuracy');
    expect(
      catalog.supportingData['marketIds'],
      containsPair('Crystallized Energy of Endtimes', '821252'),
    );
    for (final name in const <String>[
      'Essence of Dawn',
      'Essence of Dawn - Accuracy',
      "Essence of Dawn - Black Spirit's Rage",
      'Essence of Dawn - Damage Reduction',
      'Essence of Dawn - Evasion',
      'Purified Lightstone',
      'Mass of Pure Magic',
      'Ancient Spirit Dust',
      'Sharp Black Crystal Shard',
      'Melody of the Stars',
      'Origin of Eltro',
      'Origin of Margoria',
      'Origin of Rusalka',
      'Origin of Serni',
      'Trace of Despair',
      'Translucent Crystal',
      'Violet Crystal',
      'Black Gem Fragment',
      'Black Stone (Armor)',
      'Hard Black Crystal Shard',
      'Concentrated Magical Black Stone (Armor)',
    ]) {
      expect(
        catalog.processing.items[name]?.role,
        RecipeRole.manualConversion,
        reason: '$name must never be expanded automatically',
      );
      expect(catalog.processing.items[name]?.isCraftable, isFalse);
    }
    for (final name in const <String>[
      'Fragment of All Creations',
      'Legacy of the Ancient',
    ]) {
      expect(
        catalog.processing.items[name]?.role,
        RecipeRole.production,
        reason: '$name has a reviewed low-cost automatic route',
      );
      expect(catalog.processing.items[name]?.isCraftable, isTrue);
    }
    for (final name in const <String>[
      'Crystallized Energy of Endtimes',
      'Memory Fragment',
      'Oquilla Earth Crystal',
      'Oquilla Sky Crystal',
      'Piece of Edana',
      "Kydict's Heirloom",
    ]) {
      expect(catalog.processing.items[name]?.role, RecipeRole.salvage);
      expect(catalog.processing.items[name]?.isCraftable, isFalse);
    }
    final flame = catalog.processing.items['Flame of the Primordial'];
    expect(flame?.role, RecipeRole.production);
    expect(flame?.ingredients.single.name, 'Embers of the Primordial');
    expect(flame?.ingredients.single.quantity, 100);
    final marketIds =
        catalog.supportingData['marketIds'] as Map<String, Object?>;
    for (final name in const <String>[
      'Black Stone (Armor)',
      'Hard Black Crystal Shard',
      'Concentrated Magical Black Stone (Armor)',
      'Trace of Despair',
    ]) {
      expect(catalog.processing.items[name]?.marketId, isNull);
      expect(marketIds, isNot(contains(name)));
    }
    expect(
      catalog.collisions
          .where((collision) => collision.jsonPath == r'$.marketIds')
          .every((collision) => collision.valuesEqual),
      isTrue,
    );
  });

  test('bundles the three current Cron Meals and every processing route', () {
    final catalog = const BundledCatalogParser().parse(source);
    final recipes = catalog.processing.items;

    expect(recipes, isNot(contains('Savory Cron Meal')));
    expect(recipes, isNot(contains('Energizing Cron Meal')));
    expect(
      catalog.processing.searchAliases['Seafood Cron Meal'],
      contains('savory cron meal'),
    );
    expect(
      catalog.processing.searchAliases['Simple Cron Meal'],
      contains('energizing cron meal'),
    );

    for (final entry in const <String, String>{
      'Ancient Cron Spice': '9019',
      "Nadia Rowen's Special Sauce": '820015',
    }.entries) {
      final material = recipes[entry.key]!;
      expect(material.marketId, entry.value, reason: entry.key);
      expect(material.isCraftable, isFalse, reason: entry.key);
      expect(material.ingredients, isEmpty, reason: entry.key);
    }

    const expectedMarketIds = <String, String>{
      'Seafood Cron Meal': '9691',
      'Simple Cron Meal': '9692',
      'Exquisite Cron Meal': '9693',
    };
    const expectedDefaults = <String, String>{
      'Seafood Cron Meal': 'calpheon-margoria-1x',
      'Simple Cron Meal': 'combat-rations-1x',
      'Exquisite Cron Meal': 'standard-1x',
    };
    const expectedVariants = <String, Map<String, List<String>>>{
      'Seafood Cron Meal': <String, List<String>>{
        'calpheon-margoria-1x': <String>[
          'Balenos Meal:3.0',
          'Calpheon Meal:3.0',
          'Margoria Seafood Meal:1.0',
          'Ancient Cron Spice:1.0',
        ],
        'calpheon-margoria-10x': <String>[
          'Balenos Meal:30.0',
          'Calpheon Meal:30.0',
          'Margoria Seafood Meal:10.0',
          'Ancient Cron Spice:10.0',
          "Nadia Rowen's Special Sauce:1.0",
        ],
        'sute-savory-1x': <String>[
          'Balenos Meal:3.0',
          'Sute Tea:3.0',
          'Savory Steak:1.0',
          'Ancient Cron Spice:1.0',
        ],
        'sute-savory-10x': <String>[
          'Balenos Meal:30.0',
          'Sute Tea:30.0',
          'Savory Steak:10.0',
          'Ancient Cron Spice:10.0',
          "Nadia Rowen's Special Sauce:1.0",
        ],
      },
      'Simple Cron Meal': <String, List<String>>{
        'combat-rations-1x': <String>[
          'Knight Combat Rations:1.0',
          'Mediah Meal:3.0',
          'Valencia Meal:3.0',
          'Ancient Cron Spice:1.0',
        ],
        'combat-rations-10x': <String>[
          'Knight Combat Rations:10.0',
          'Mediah Meal:30.0',
          'Valencia Meal:30.0',
          'Ancient Cron Spice:10.0',
          "Nadia Rowen's Special Sauce:1.0",
        ],
        'drieghanese-1x': <String>[
          'Special Drieghanese Meal:1.0',
          'Serendia Meal:3.0',
          'Mediah Meal:3.0',
          'Ancient Cron Spice:1.0',
        ],
        'drieghanese-10x': <String>[
          'Special Drieghanese Meal:10.0',
          'Serendia Meal:30.0',
          'Mediah Meal:30.0',
          'Ancient Cron Spice:10.0',
          "Nadia Rowen's Special Sauce:1.0",
        ],
      },
      'Exquisite Cron Meal': <String, List<String>>{
        'standard-1x': <String>[
          'Serendia Meal:3.0',
          'Special Arehaza Meal:1.0',
          'Kamasylvia Meal:3.0',
          'Ancient Cron Spice:1.0',
        ],
        'standard-10x': <String>[
          'Serendia Meal:30.0',
          'Special Arehaza Meal:10.0',
          'Kamasylvia Meal:30.0',
          'Ancient Cron Spice:10.0',
          "Nadia Rowen's Special Sauce:1.0",
        ],
      },
    };
    const higherGradeOptions = <String, String>{
      'Balenos Meal': 'Special Balenos Meal',
      'Calpheon Meal': 'Special Calpheon Meal',
      'Sute Tea': 'Healthy Sute Tea',
      'Mediah Meal': 'Special Mediah Meal',
      'Valencia Meal': 'Special Valencia Meal',
      'Serendia Meal': 'Special Serendia Meal',
      'Kamasylvia Meal': 'Special Kamasylvia Meal',
    };

    for (final recipeEntry in expectedVariants.entries) {
      final recipe = recipes[recipeEntry.key]!;
      expect(recipe.marketId, expectedMarketIds[recipeEntry.key]);
      expect(recipe.defaultVariantId, expectedDefaults[recipeEntry.key]);
      expect(recipe.method, 'Simple Cooking');
      expect(recipe.variantBatchMultipliers, <int>[1, 10]);
      expect(
        recipe.variants.map((variant) => variant.id).toSet(),
        recipeEntry.value.keys.toSet(),
      );

      for (final variantEntry in recipeEntry.value.entries) {
        final variant = recipe.variants.singleWhere(
          (candidate) => candidate.id == variantEntry.key,
        );
        final expectedBatch = variant.id.endsWith('-10x') ? 10 : 1;
        expect(variant.batchMultiplier, expectedBatch);
        expect(variant.baseOutput, expectedBatch.toDouble());
        expect(variant.outputMinimum, expectedBatch.toDouble());
        expect(variant.outputMaximum, expectedBatch.toDouble());
        expect(_ingredientRowsForVariant(variant), variantEntry.value);

        for (final ingredient in variant.ingredients) {
          final higherGrade = higherGradeOptions[ingredient.name];
          if (higherGrade == null) {
            continue;
          }
          expect(ingredient.options, <String>[ingredient.name, higherGrade]);
          expect(ingredient.substituteRatios[ingredient.name], 1);
          expect(
            ingredient.substituteRatios[higherGrade],
            closeTo(1 / 3, 1e-12),
          );
        }
      }
    }
  });

  test('every resource-map material has bundled in-game artwork', () {
    final catalog = const BundledCatalogParser().parse(source);
    final repository = CatalogRepository(catalog);
    final map =
        jsonDecode(
              File(
                'packages/bdo_map_core/assets/data/resource_map.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final resources = (map['resources']! as List<Object?>)
        .cast<Map<String, Object?>>();

    for (final resource in resources) {
      final name = resource['name']! as String;
      final aliases = (resource['aliases']! as List<Object?>).cast<String>();
      expect(
        CraftMode.values.any(
          (mode) =>
              repository.iconDataUri(mode, name, aliases: aliases) != null,
        ),
        isTrue,
        reason: '$name must use bundled in-game item artwork',
      );
    }
  });

  test('processing outputs come from each bundled recipe result record', () {
    final catalog = const BundledCatalogParser().parse(source);
    final recipes = catalog.processing.items;

    expect(processingOutputPerCraft(recipe: recipes['Acacia Plank']!), 2.5);
    expect(
      processingOutputPerCraft(recipe: recipes['Concentrated Herbal Juice']!),
      4.5,
    );
    expect(processingOutputPerCraft(recipe: recipes['Magical Shard']!), 1);
    expect(
      processingOutputPerCraft(recipe: recipes['Purified Lightstone']!),
      2,
      reason: 'an exact recorded output must not be multiplied by 2.5',
    );

    final legacyUnbounded = recipes.values
        .where(
          (recipe) =>
              recipe.isCraftable &&
              recipe.outputMinimum == null &&
              recipe.outputMaximum == null,
        )
        .map((recipe) => recipe.name);
    expect(
      legacyUnbounded,
      unorderedEquals(const <String>[
        'Melted Copper Shard',
        'Melted Gold Shard',
        'Melted Iron Shard',
        'Melted Lead Shard',
        'Melted Platinum Shard',
        'Melted Silver Shard',
        'Melted Tin Shard',
        'Melted Titanium Shard',
        'Melted Vanadium Shard',
        'Melted Zinc Shard',
        'Pure Copper Crystal',
        'Pure Gold Crystal',
        'Pure Iron Crystal',
        'Pure Lead Crystal',
        'Pure Platinum Crystal',
        'Pure Silver Crystal',
        'Pure Tin Crystal',
        'Pure Titanium Crystal',
        'Pure Vanadium Crystal',
        'Pure Zinc Crystal',
      ]),
      reason:
          'new unbounded processing recipes require a reviewed result record',
    );

    for (final recipe in recipes.values.where((value) => value.isCraftable)) {
      final output = processingOutputPerCraft(recipe: recipe);
      expect(output.isFinite, isTrue, reason: recipe.name);
      expect(output, isPositive, reason: recipe.name);
      for (final variant in recipe.variants) {
        final variantOutput = processingOutputPerCraft(
          recipe: recipe.resolveVariant(variant.id),
        );
        expect(
          variantOutput.isFinite,
          isTrue,
          reason: '${recipe.name}/${variant.id}',
        );
        expect(
          variantOutput,
          isPositive,
          reason: '${recipe.name}/${variant.id}',
        );
      }
    }
  });

  test('locks the reviewed Edania Part II recipes and supporting data', () {
    final catalog = const BundledCatalogParser().parse(source);
    final repository = CatalogRepository(catalog);

    final perfume = catalog.alchemy.items['Perfume of Verdure']!;
    expect(perfume.marketId, '890');
    expect(perfume.variantRoutes.map((route) => route.id), <String>[
      'alchemy-tool',
      'simple-alchemy',
    ]);
    expect(perfume.resolveVariant('alchemy-tool').type, 'alchemy');
    expect(
      perfume.resolveVariant('alchemy-tool').method,
      'Alchemy Tool (Skilled 1+)',
    );
    expect(_ingredientRows(perfume.resolveVariant('alchemy-tool')), <String>[
      'Trace of Nature:5.0',
      'Everlasting Herb:5.0',
      'Clear Liquid Reagent:5.0',
      'Oil of Tranquility:6.0',
      'Magical Olivine Powder:50.0',
    ]);
    expect(perfume.resolveVariant('simple-alchemy').type, 'simple_alchemy');
    expect(_ingredientRows(perfume.resolveVariant('simple-alchemy')), <String>[
      'Perfume of Swiftness:1.0',
      'Shining Powder:3.0',
      'Magical Olivine Powder:35.0',
    ]);

    final viridian = catalog.alchemy.items['Viridian Draught']!;
    expect(viridian.type, 'simple_alchemy');
    expect(viridian.outputMinimum, 1);
    expect(_ingredientRows(viridian), <String>[
      'Elixir of Mastery:3.0',
      'Elixir of Time:3.0',
      'Tears of the Falling Moon:1.0',
      'Magical Olivine Powder:10.0',
    ]);
    expect(
      viridian.ingredients.first.substituteRatios['Elixir of Improved Mastery'],
      closeTo(1 / 3, 0.0000001),
    );
    expect(
      viridian.ingredients[1].substituteRatios['Elixir of Flowing Time'],
      closeTo(1 / 3, 0.0000001),
    );

    for (final slot in const <String>['Necklace', 'Earring', 'Ring', 'Belt']) {
      final causality =
          catalog.processing.items['Causality Shardstone - $slot']!;
      expect(causality.variantBatchMultipliers, <int>[1, 10]);
      expect(_ingredientRows(causality.resolveVariant('heating-1x')), <String>[
        'Twilight of the End - $slot:5.0',
        'Caphras Stone:10.0',
        'Magical Shard:10.0',
        'Essence of Dawn:10.0',
      ]);
      expect(_ingredientRows(causality.resolveVariant('heating-10x')), <String>[
        'Twilight of the End - $slot:50.0',
        'Caphras Stone:100.0',
        'Magical Shard:100.0',
        'Essence of Dawn:100.0',
        'Black Stone Powder:1.0',
      ]);
      expect(causality.resolveVariant('heating-10x').outputMinimum, 10);

      final apeiron = catalog.processing.items['Apeiron $slot']!;
      expect(apeiron.marketId, isNotNull);
      expect(_ingredientRows(apeiron), <String>[
        'Twilight of the End - $slot:10.0',
        'Caphras Stone:10.0',
        'Magical Shard:10.0',
      ]);

      final ekleta = catalog.processing.items['Ekleta $slot']!;
      expect(ekleta.role, RecipeRole.manualConversion);
      expect(ekleta.isCraftable, isFalse);
      expect(ekleta.ingredients, isEmpty);
      expect(ekleta.method, 'Quest Exchange');
    }

    const reformRecipes = <String, List<String>>{
      'Dawnbound Ekleta Necklace': <String>[
        'Ekleta Necklace:1.0',
        'Cup of Destined Dawn:1.0',
      ],
      'Dawnbound Apeiron Necklace': <String>[
        'Apeiron Necklace:1.0',
        'Cup of Destined Dawn:1.0',
      ],
      'Moonhushed Ekleta Earring': <String>[
        'Ekleta Earring:1.0',
        'Cup of Reticent Moonbeams:1.0',
      ],
      'Moonhushed Apeiron Earring': <String>[
        'Apeiron Earring:1.0',
        'Cup of Reticent Moonbeams:1.0',
      ],
      'Sunstarved Ekleta Ring': <String>[
        'Ekleta Ring:1.0',
        'Cup of Callous Sun:1.0',
      ],
      'Sunstarved Apeiron Ring': <String>[
        'Apeiron Ring:1.0',
        'Cup of Callous Sun:1.0',
      ],
      'Duskborne Ekleta Belt': <String>[
        'Ekleta Belt:1.0',
        'Cup of Burgeoning Dusk:1.0',
      ],
      'Duskborne Apeiron Belt': <String>[
        'Apeiron Belt:1.0',
        'Cup of Burgeoning Dusk:1.0',
      ],
    };
    for (final entry in reformRecipes.entries) {
      final recipe = catalog.processing.items[entry.key]!;
      expect(recipe.role, RecipeRole.manualConversion, reason: entry.key);
      expect(recipe.isCraftable, isFalse, reason: entry.key);
      expect(recipe.method, 'Item Reform', reason: entry.key);
      expect(_ingredientRows(recipe), entry.value, reason: entry.key);
      expect(recipe.marketId, isNull, reason: entry.key);
    }

    const crateInputs = <String, String>{
      'Magnetite Ore Crate': 'Magnetite Ore',
      'Rough Marble Crate': 'Rough Marble',
      'Magnetite Ingot Crate': 'Magnetite Ingot',
      'Marble Crate': 'Polished Marble',
    };
    for (final entry in crateInputs.entries) {
      final recipe = catalog.processing.items[entry.key]!;
      expect(recipe.role, RecipeRole.manualConversion, reason: entry.key);
      expect(recipe.isCraftable, isFalse, reason: entry.key);
      expect(recipe.method, 'Mineral Workshop', reason: entry.key);
      expect(_ingredientRows(recipe), <String>[
        '${entry.value}:10.0',
        'Black Stone Powder:1.0',
      ], reason: entry.key);
    }

    const godslayerRoutes = <String, String>{
      "Edana - Godslayer's Courage Box": 'Embers of Ynix - Helmet',
      "Edana - Godslayer's Abstinence Box": 'Embers of Ynix - Armor',
      "Edana - Godslayer's Justice Box": 'Embers of Ynix - Gloves',
      "Edana - Godslayer's Wisdom Box": 'Embers of Ynix - Shoes',
    };
    for (final entry in godslayerRoutes.entries) {
      final ember = catalog.processing.items[entry.value]!;
      final box = catalog.processing.items[entry.key]!;
      expect(ember.role, RecipeRole.manualConversion, reason: entry.value);
      expect(ember.ingredients, isEmpty, reason: entry.value);
      expect(box.role, RecipeRole.manualConversion, reason: entry.key);
      expect(box.isCraftable, isFalse, reason: entry.key);
      expect(box.method, 'Quest Exchange', reason: entry.key);
      expect(_ingredientRows(box), <String>['${entry.value}:100.0']);
    }

    for (final tier in const <String>['WON', 'BON', 'JIN', 'HAN']) {
      final crystal =
          catalog.processing.items['$tier Wandering Origin Crystal']!;
      expect(crystal.marketId, isNull);
      expect(_ingredientRows(crystal), <String>[
        '$tier Origin Shard:100.0',
        'Caphras Stone:100.0',
        'Magical Shard:100.0',
      ]);
    }

    final fused = catalog.processing.items['Fused Crystal of Decimation']!;
    expect(fused.marketId, '15298');
    expect(_ingredientRows(fused), <String>[
      'Crystal of Brutal Decimation:1.0',
      'Fusion Shard:30.0',
      'Caphras Stone:100.0',
      'Magical Lightstone Crystal:300.0',
      'Black Stone:500.0',
    ]);

    final hanReforge = catalog.processing.items.entries
        .where((entry) => entry.key.startsWith('HAN Reforge Stone - '))
        .toList(growable: false);
    expect(hanReforge, hasLength(11));
    for (final entry in hanReforge) {
      expect(entry.value.ingredients, hasLength(5), reason: entry.key);
      expect(entry.value.ingredients[0].quantity, 5, reason: entry.key);
      expect(entry.value.ingredients[1].name, "Nev's Fragment");
      expect(entry.value.ingredients[1].quantity, 30);
      expect(entry.value.ingredients[4].name, 'Magical Lightstone Crystal');
      expect(entry.value.ingredients[4].quantity, 200);
    }

    expect(
      _ingredientRows(catalog.processing.items["Margahan's Artifact"]!),
      <String>[
        "Margahan's Fragment:100.0",
        'Pure Magnetite Crystal:100.0',
        'Pure Marble:100.0',
      ],
    );
    final olivine = catalog.processing.items['Magical Olivine Powder']!;
    expect(olivine.outputMinimum, 4);
    expect(olivine.outputMaximum, 6);
    expect(_ingredientRows(olivine), <String>[
      'Olivine Ore:1.0',
      'Pure Powder Reagent:1.0',
    ]);

    expect(
      _ingredientRows(catalog.processing.items['Polished Marble']!),
      <String>['Rough Marble:10.0'],
    );
    expect(_ingredientRows(catalog.processing.items['Pure Marble']!), <String>[
      'Polished Marble:3.0',
      'Metal Solvent:2.0',
    ]);
    expect(
      _ingredientRows(catalog.processing.items['Melted Magnetite Shard']!),
      <String>['Magnetite Ore:5.0'],
    );
    expect(
      _ingredientRows(catalog.processing.items['Magnetite Ingot']!),
      <String>['Melted Magnetite Shard:10.0'],
    );
    expect(
      _ingredientRows(catalog.processing.items['Pure Magnetite Crystal']!),
      <String>['Magnetite Ingot:3.0', 'Metal Solvent:2.0'],
    );

    final dawn = catalog.processing.items['Dawn Black Stone']!;
    expect(dawn.variantBatchMultipliers, <int>[1, 10]);
    expect(_ingredientRows(dawn.resolveVariant('heating-1x')), <String>[
      'Essence of Dawn:20.0',
    ]);
    expect(_ingredientRows(dawn.resolveVariant('heating-10x')), <String>[
      'Essence of Dawn:200.0',
      'Black Stone Powder:1.0',
    ]);

    final supporting = catalog.supportingData;
    final review = supporting['edaniaPartIiReview'] as Map<String, Object?>;
    expect(
      review['officialSources'],
      containsAll(<String>[
        'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10451&countryType=en-US',
        'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19693',
      ]),
    );
    expect(review['referenceItems'], hasLength(24));
    expect(review['inferredProcessingOutputs'], hasLength(5));
    final unresolved = (review['unresolvedItems']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(unresolved, hasLength(1));
    expect(unresolved.single['name'], 'Causality Hammer');
    expect(unresolved.single['itemId'], isNull);
    final pending = (review['pendingMarketVerification']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      pending.map((entry) => entry['name']),
      containsAll(<String>[
        'Causality Shardstone - Necklace',
        'WON Origin Shard',
        'HAN Reforge Stone - All AP',
        'Dawn Black Stone',
        'Rough Marble',
        'Polished Marble',
        'Magnetite Ore',
        'Melted Magnetite Shard',
        'Magnetite Ingot',
      ]),
    );
    final marketIds = supporting['marketIds'] as Map<String, Object?>;
    for (final name in pending.map((entry) => entry['name']! as String)) {
      expect(marketIds, isNot(contains(name)), reason: name);
    }
    expect(marketIds['Apeiron Necklace'], '11733');
    expect(marketIds['Fused Crystal of Decimation'], '15298');

    final itemWeightIds = supporting['itemWeightIds'] as Map<String, Object?>;
    final itemWeights = supporting['itemWeightsLtById'] as Map<String, Object?>;
    expect(itemWeightIds['Perfume of Verdure'], '890');
    expect(itemWeights['890'], 0.2);
    expect(itemWeightIds['Apeiron Ring'], '12144');
    expect(itemWeights['12144'], 0.17);
    expect(itemWeightIds['Ekleta Necklace'], '11731');
    expect(itemWeights['11731'], 1);
    expect(itemWeightIds['Dawnbound Apeiron Necklace'], '11734');
    expect(itemWeights['11734'], 1);
    expect(itemWeightIds['Magnetite Ore Crate'], '55445');
    expect(itemWeights['55445'], 30);
    expect(itemWeightIds['Embers of Ynix - Helmet'], '821461');
    expect(itemWeights['821461'], 0.1);
    for (final name in const <String>[
      'Causality Shardstone - Necklace',
      'Apeiron Necklace',
      'WON Origin Shard',
      'WON Wandering Origin Crystal',
      'Fused Crystal of Decimation',
      'HAN Reforge Stone - All AP',
      "Margahan's Artifact",
      'Magical Olivine Powder',
      'Rough Marble',
      'Polished Marble',
      'Pure Marble',
      'Magnetite Ore',
      'Melted Magnetite Shard',
      'Magnetite Ingot',
      'Pure Magnetite Crystal',
      'Perfume of Verdure',
      'Viridian Draught',
      'Dawn Black Stone',
      'Ekleta Necklace',
      'Dawnbound Ekleta Necklace',
      'Dawnbound Apeiron Necklace',
      'Magnetite Ore Crate',
      'Embers of Ynix - Helmet',
      "Edana - Godslayer's Courage Box",
    ]) {
      expect(
        CraftMode.values.any(
          (mode) => repository.iconDataUri(mode, name) != null,
        ),
        isTrue,
        reason: '$name needs verified bundled artwork',
      );
    }
  });

  test('recipe roles parse explicitly and reject unsafe unknown values', () {
    expect(
      RecipeRole.fromCatalogValue('manual_conversion'),
      RecipeRole.manualConversion,
    );
    expect(
      RecipeRole.fromCatalogValue('manual-conversion'),
      RecipeRole.manualConversion,
    );
    expect(RecipeRole.fromCatalogValue('salvage'), RecipeRole.salvage);
    expect(
      () => RecipeRole.fromCatalogValue('automatic-ish'),
      throwsFormatException,
    );
  });

  test('preserves substitute metadata on production ingredients', () {
    final catalog = const BundledCatalogParser().parse(source);
    final rows = catalog.cooking.items.values
        .expand((recipe) => recipe.ingredients)
        .where((ingredient) => ingredient.options.isNotEmpty)
        .toList();

    expect(rows, isNotEmpty);
    expect(
      rows.any((ingredient) => ingredient.substituteGroup != null),
      isTrue,
    );
    expect(
      rows.any((ingredient) => ingredient.substituteRatios.isNotEmpty),
      isTrue,
    );
  });

  test('preserves complete correlated processing recipe variants', () {
    final catalog = const BundledCatalogParser().parse(source);

    final adhesive = catalog.processing.items['Adhesive for Upgrade']!;
    expect(adhesive.defaultVariantId, 'single-sap');
    expect(adhesive.variants.map((variant) => variant.id), <String>[
      'single-sap',
      'mixed-saps',
    ]);
    expect(
      adhesive
          .resolveVariant('mixed-saps')
          .ingredients
          .map((ingredient) => '${ingredient.name}:${ingredient.quantity}'),
      <String>[
        'White Cedar Sap:100.0',
        'Acacia Sap:100.0',
        'Elder Tree Sap:100.0',
        "Sea Monster's Ooze:1.0",
      ],
    );

    final powder = catalog.processing.items['Insectivore Plant Powder']!;
    expect(
      powder
          .resolveVariant('leaves-and-fragments')
          .ingredients
          .map((ingredient) => ingredient.name),
      <String>['Insectivore Plant Leaf', 'Tree Spirit Stone Fragment'],
    );

    final blackGemFragment = catalog.processing.items['Black Gem Fragment']!;
    expect(blackGemFragment.isCraftable, isFalse);
    expect(blackGemFragment.variants, hasLength(5));
    expect(
      blackGemFragment
          .resolveVariant('red-rifts-branch')
          .ingredients
          .map((ingredient) => ingredient.name),
      <String>[
        'Red Crystal',
        'Powder of Rifts',
        "Monk's Branch",
        'Fire Horn',
        'Pig Blood',
      ],
    );
  });

  test('preserves declared route and batch formula matrices', () {
    final catalog = const BundledCatalogParser().parse(source);

    final chaotic = catalog.processing.items['Flawless Chaotic Black Stone']!;
    expect(chaotic.variantRoutes.map((route) => route.id), <String>[
      'raw-materials',
      'flawless-magical',
    ]);
    expect(chaotic.variantBatchMultipliers, <int>[1, 10]);
    expect(
      chaotic
          .variantForRouteAndBatch('raw-materials', 10)!
          .ingredients
          .map((ingredient) => '${ingredient.name}:${ingredient.quantity}'),
      <String>[
        'Sharp Black Crystal Shard:20.0',
        'Caphras Stone:100.0',
        'Mass of Pure Magic:10.0',
        'Black Stone Powder:1.0',
      ],
    );
    expect(
      chaotic
          .variantForRouteAndBatch('flawless-magical', 10)!
          .ingredients
          .map((ingredient) => '${ingredient.name}:${ingredient.quantity}'),
      <String>[
        'Caphras Stone:100.0',
        'Black Stone Powder:1.0',
        'Flawless Magical Black Stone:10.0',
      ],
    );

    final blackGem = catalog.processing.items['Black Gem']!;
    expect(blackGem.variantRoutes, hasLength(1));
    expect(blackGem.variantBatchMultipliers, <int>[1, 10, 100]);
    expect(blackGem.resolveVariant('standard-100x').baseOutput, 40);
    expect(blackGem.resolveVariant('standard-100x').outputMinimum, 100);
    expect(
      blackGem
          .resolveVariant('standard-100x')
          .ingredients
          .map((ingredient) => '${ingredient.name}:${ingredient.quantity}'),
      <String>[
        'Black Gem Fragment:100.0',
        'Black Stone:200.0',
        'Pure Powder Reagent:1.0',
      ],
    );

    final aether = catalog.processing.items['Brimming Essence of Aether']!;
    expect(aether.variantRoutes.map((route) => route.id), <String>[
      'sharp-shards',
      'oquilla-pieces',
    ]);
    expect(aether.variantBatchMultipliers, <int>[1, 10]);
    expect(
      aether
          .variantForRouteAndBatch('oquilla-pieces', 10)!
          .ingredients
          .map((ingredient) => '${ingredient.name}:${ingredient.quantity}'),
      <String>[
        'Black Stone Powder:1.0',
        'Oquilla Piece of the Old Moon:20.0',
        'Faint Essence of Aether:10.0',
      ],
    );
  });

  test('uses current direct Ultimate Reform Stone workshop recipes', () {
    final catalog = const BundledCatalogParser().parse(source);
    final armor = catalog.processing.items['Ultimate Armor Reform Stone']!;
    final weapon = catalog.processing.items['Ultimate Weapon Reform Stone']!;

    expect(armor.method, 'Refinery Lv. 3');
    expect(
      armor.ingredients.map(
        (ingredient) => '${ingredient.name}:${ingredient.quantity}',
      ),
      <String>[
        'Steel:40.0',
        'Sharp Black Crystal Shard:1.0',
        'Black Crystal:30.0',
        'Old Tree Bark:20.0',
        "Clown's Blood:20.0",
        'Black Stone Powder:400.0',
      ],
    );
    expect(weapon.method, 'Refinery Lv. 3');
    expect(
      weapon.ingredients.map(
        (ingredient) => '${ingredient.name}:${ingredient.quantity}',
      ),
      <String>[
        'Steel:50.0',
        'Sharp Black Crystal Shard:1.0',
        'Black Crystal:30.0',
        'Red Tree Lump:20.0',
        "Clown's Blood:20.0",
        'Black Stone Powder:400.0',
      ],
    );

    final legacyUnavailable =
        catalog.supportingData['legacyUnavailableItems'] as List<Object?>;
    expect(
      legacyUnavailable,
      containsAll(<String>[
        'Grade 3 Armor Reform Stone',
        'Grade 3 Weapon Reform Stone',
      ]),
    );
  });

  test(
    'locks the complete supported batch output catalog and full formulas',
    () {
      final catalog = const BundledCatalogParser().parse(source);
      final actualBatchOutputs = catalog.processing.items.entries
          .where((entry) => entry.value.variantBatchMultipliers.length > 1)
          .map((entry) => entry.key)
          .toSet();

      expect(actualBatchOutputs, hasLength(116));
      expect(actualBatchOutputs, _supportedBatchOutputNames);

      final rawRoot = jsonDecode(source) as Map<String, dynamic>;
      final rawProcessing = rawRoot['processing'] as Map<String, dynamic>;
      final rawItems = rawProcessing['items'] as Map<String, dynamic>;
      for (final name in _supportedBatchOutputNames.difference(
        _previouslySupportedBatchOutputNames,
      )) {
        final rawRecipe = rawItems[name] as Map<String, dynamic>;
        final variants = rawRecipe['variants'] as List<dynamic>;
        expect(variants, isNotEmpty, reason: name);
        for (final rawVariant in variants) {
          final variant = rawVariant as Map<String, dynamic>;
          for (final field in const <String>[
            'routeId',
            'batchMultiplier',
            'baseOutput',
            'outputMin',
            'outputMax',
            'ingredients',
          ]) {
            expect(
              variant,
              contains(field),
              reason: '$name/${variant['id']} must explicitly store $field',
            );
          }
          expect(
            variant['ingredients'] as List<dynamic>,
            isNotEmpty,
            reason:
                '$name/${variant['id']} needs a complete ingredient formula',
          );
        }
      }

      final magicalShard = catalog.processing.items['Magical Shard']!;
      expect(magicalShard.variantBatchMultipliers, <int>[1, 10]);
      final magicalShardBase = magicalShard.resolveVariant('standard');
      final magicalShardBulk = magicalShard.resolveVariant('standard-10x');
      expect(_ingredientRows(magicalShardBase), <String>[
        'Sealed Black Magic Crystal:1.0',
      ]);
      expect(_ingredientRows(magicalShardBulk), <String>[
        'Sealed Black Magic Crystal:10.0',
        'Black Stone Powder:1.0',
      ]);
      expect(
        magicalShardBulk.ingredients.first.options,
        magicalShardBase.ingredients.first.options,
      );
      expect(magicalShardBulk.ingredients.first.options, hasLength(20));

      final lethal = catalog.processing.items['Elixir of Lethal Destruction']!;
      expect(lethal.defaultVariantId, 'standard');
      expect(lethal.baseOutput, 0.4);
      expect(lethal.outputMinimum, 1);
      expect(_ingredientRows(lethal), <String>[
        'Elixir of Destruction:3.0',
        'Blue Reagent:1.0',
      ]);
      expect(_ingredientRows(lethal.resolveVariant('standard-10x')), <String>[
        'Elixir of Destruction:30.0',
        'Blue Reagent:10.0',
        "Ibellab's Essence:1.0",
      ]);

      final wave = catalog.processing.items['Wave Residue Adhesive']!;
      expect(wave.baseOutput, 0.4);
      expect(_ingredientRows(wave.resolveVariant('standard-10x')), <String>[
        "Violent Sea Monster's Ooze:10.0",
        'Starlight Emulsifier:10.0',
        'Black Stone Powder:1.0',
      ]);

      final caphras = catalog.processing.items['Caphras Stone']!;
      expect(caphras.variantBatchMultipliers, <int>[1, 10, 100]);
      expect(_ingredientRows(caphras.resolveVariant('standard-100x')), <String>[
        'Ancient Spirit Dust:500.0',
        'Black Stone:100.0',
        'Pure Powder Reagent:1.0',
      ]);

      final damagedHide = catalog.processing.items['Damaged Hide']!;
      expect(damagedHide.resolveVariant('standard').baseOutput, 0.8);
      expect(damagedHide.resolveVariant('standard').outputMinimum, 2);
      expect(damagedHide.resolveVariant('standard-10x').baseOutput, 8);
      expect(damagedHide.resolveVariant('standard-10x').outputMinimum, 20);

      final primordial = catalog.processing.items['Primordial Black Stone']!;
      final primordialBulk = primordial.resolveVariant('standard-10x');
      expect(primordialBulk.baseOutput, 4);
      expect(primordialBulk.outputMinimum, 10);
      expect(primordialBulk.outputMaximum, 10);
      expect(_ingredientRows(primordialBulk), <String>[
        'Black Stone Powder:1.0',
        'Sharp Black Crystal Shard:20.0',
        'Caphras Stone:100.0',
        'Primordial Crystal:10.0',
      ]);

      final concentratedHerbal =
          catalog.processing.items['Concentrated Herbal Juice']!;
      expect(
        concentratedHerbal.variantRoutes.map((route) => route.id),
        <String>['high-quality-herbs', 'herbal-juice'],
      );
      expect(concentratedHerbal.variantBatchMultipliers, <int>[1, 10, 100]);
      expect(
        _ingredientRowsForVariant(
          concentratedHerbal.variantForRouteAndBatch('herbal-juice', 100)!,
        ),
        <String>['Herbal Juice:300.0', 'Sun-Dried Salt:2.0'],
      );
      expect(
        concentratedHerbal
            .variantForRouteAndBatch('high-quality-herbs', 1)!
            .outputMinimum,
        3,
      );
      expect(
        concentratedHerbal
            .variantForRouteAndBatch('high-quality-herbs', 1)!
            .outputMaximum,
        6,
      );

      final refinedGrain = catalog.processing.items['Refined Grain Juice']!;
      expect(refinedGrain.variantRoutes.map((route) => route.id), <String>[
        'refined-juice',
      ]);
      expect(refinedGrain.variantBatchMultipliers, <int>[1, 10, 100]);
      expect(
        _ingredientRows(refinedGrain.resolveVariant('refined-juice-10x')),
        <String>['Highly Concentrated Grain Juice:30.0', 'Sugar:1.0'],
      );

      final blessing =
          catalog.processing.items['Blessing of Mystic Beasts - All AP']!;
      expect(blessing.variantRoutes.map((route) => route.id), <String>[
        'parchment',
        'supreme-hide',
      ]);
      expect(blessing.variantBatchMultipliers, <int>[1, 10]);
      expect(
        _ingredientRowsForVariant(
          blessing.variantForRouteAndBatch('parchment', 10)!,
        ),
        <String>[
          'Lightstone of Fire: Rage:1.0',
          'Remnants of Mystic Beasts:100.0',
          'Mystical Parchment:100.0',
          'Magical Lightstone Crystal:3600.0',
          'Black Stone Powder:1.0',
        ],
      );
      expect(
        blessing
            .variantForRouteAndBatch('parchment', 10)!
            .ingredients
            .first
            .quantity,
        1,
        reason: 'The fixed 10x formula does not scale its Lightstone.',
      );

      for (final name in const <String>[
        'Sharp Black Crystal Shard',
        'Hard Black Crystal Shard',
      ]) {
        final recipe = catalog.processing.items[name]!;
        expect(recipe.isReferenceOnly, isTrue, reason: name);
        expect(recipe.variants, isEmpty, reason: name);
      }
    },
  );
}

List<String> _ingredientRows(Recipe recipe) => recipe.ingredients
    .map((ingredient) => '${ingredient.name}:${ingredient.quantity}')
    .toList(growable: false);

List<String> _ingredientRowsForVariant(RecipeVariant variant) => variant
    .ingredients
    .map((ingredient) => '${ingredient.name}:${ingredient.quantity}')
    .toList(growable: false);

const _previouslySupportedBatchOutputNames = <String>{
  'Black Gem',
  'Brimming Essence of Aether',
  'Concentrated Magical Black Gem',
  'Concentrated Magical Black Stone',
  "Edana's Black Stone",
  'Flawless Chaotic Black Stone',
  'Flawless Magical Black Stone',
  "Krogdalo's Origin Stone",
};

const _supportedBatchOutputNames = <String>{
  ..._previouslySupportedBatchOutputNames,
  'Improved Elixir of Amity',
  'Elixir of Sharp Thorn',
  'Strong Resurrection Elixir',
  'Elixir of Perfect Human Hunt',
  'Elixir of Endless Frenzy',
  'Glorious Golden Hand Elixir',
  'Elixir of Strong Draining',
  'Elixir of Fierce Demihuman Hunt',
  'Elixir of Brutal Perforation',
  'Surging Energy Elixir',
  'Soaring Wings Elixir',
  'Brutal Death Elixir',
  'Elixir of Flowing Wind',
  'Elixir of Intrepid Swiftness',
  'Elixir of Agile Spells',
  'Agile Seal Elixir',
  'Elixir of Lethal Assassin',
  'Elixir of Sharp Detection',
  'Elixir of Advanced Concentration',
  'Elixir of Remarkable Will',
  'Elixir of Endless Fury',
  'Elixir of Sharp Resistance',
  'Elixir of Strong Life',
  'Elixir of Clear Mentality',
  "Grim Soul Reaper's Elixir",
  'Splendid EXP Elixir',
  'Elixir of Steel Defense',
  'Elixir of Brutal Carnage',
  'Merciless Sky Elixir',
  'Elixir of Overwhelming Endurance',
  "Skilled Worker's Elixir",
  "Skilled Fisher's Elixir",
  "Strong Griffon's Elixir",
  'Elixir of Flowing Time',
  'Elixir of Expert Training',
  'Elixir of Strong Shock',
  'Surging Weenie Elixir',
  'Reliable Looney Elixir',
  'Splendid Helix Elixir',
  'Superior Whale Tendon Potion',
  'Tough Whale Tendon Elixir',
  'Elixir of Improved Mastery',
  'Elixir of Rough Labor',
  'Frenzy Draught',
  'Savage Draught',
  'Seafood Cron Meal',
  'Simple Cron Meal',
  'Exquisite Cron Meal',
  'Celerity Draught',
  'Armor Draught',
  "Immortal: Beast's Draught",
  "Immortal: Giant's Draught",
  'Immortal: Savage Draught',
  'Immortal: Frenzy Draught',
  'Immortal: Perfume of Spirits',
  'Immortal: Perfume of Courage',
  'Immortal: Perfume of Khalk',
  'Immortal: Perfume of Deep Sea',
  'Elixir of Indignation',
  'Immortal: Elixir of Indignation',
  'Immortal: Perfume of Insight',
  'Immortal: Armor Draught',
  'Immortal: Perfume of Charm',
  'Immortal: Perfume of Bracing Spirits',
  'Immortal: Frenzy Draught of Corruption',
  'Immortal: Fury Draught',
  'Immortal: Adaptation Draught',
  'Immortal: Potential Draught',
  'Immortal: Corruption Draught',
  'Immortal: Berserk Draught',
  'Immortal: Harmony Draught',
  'Tidal Draught',
  'Perfume of Envy',
  'Immortal: Perfume of Envy',
  'Perfume of Tenacity',
  'Immortal: Perfume of Tenacity',
  'Elixir of Lethal Destruction',
  'Elixir of Endless Persistence',
  'Elixir of Raw Brawn',
  'Perfume of Bracing Spirits',
  'Frenzy Draught of Corruption',
  'Elixir of Infinite Skill',
  'Elixir of Corrupted Armor',
  'Sturdy Whale Tendon Potion',
  'Sturdy Whale Tendon Elixir',
  'Strong Elixir of Edania',
  'Wave Residue Adhesive',
  'Magical Shard',
  'Caphras Stone',
  'Damaged Hide',
  'Usable Hide',
  'Primordial Black Stone',
  'Concentrated Herbal Juice',
  'Highly Concentrated Herbal Juice',
  'Refined Herbal Juice',
  'Concentrated Grain Juice',
  'Highly Concentrated Grain Juice',
  'Refined Grain Juice',
  'Blessing of Mystic Beasts - All AP',
  'Blessing of Mystic Beasts - Accuracy',
  'Blessing of Mystic Beasts - Max HP',
  'Blessing of Mystic Beasts - Damage Reduction',
  'Blessing of Mystic Beasts - Evasion',
  'Causality Shardstone - Necklace',
  'Causality Shardstone - Earring',
  'Causality Shardstone - Ring',
  'Causality Shardstone - Belt',
  'Dawn Black Stone',
};
