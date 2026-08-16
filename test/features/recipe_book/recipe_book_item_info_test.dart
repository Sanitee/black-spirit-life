import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_purpose.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('terminal planner leaves do not invent Gathering acquisition', () {
    final info = recipeBookInfoFor(
      name: 'Unclassified Terminal Item',
      recipe: Recipe(
        name: 'Unclassified Terminal Item',
        type: 'gathered',
        baseOutput: 1,
        group: null,
        method: null,
        ingredients: const <Ingredient>[],
        marketId: null,
        sourceNote: null,
        vendor: null,
        location: null,
        npcPrice: 0,
        qualityBase: null,
        qualityGrade: null,
        outputMinimum: null,
        outputMaximum: null,
      ),
      searchTerms: const <String>[],
      consumerRecipes: const <Recipe>[],
    );

    expect(info?.howToObtain, isEmpty);
    expect(info?.summary, isEmpty);
    expect(info?.hasBody, isTrue);
  });

  test('verified higher-grade farm materials have useful concise bodies', () {
    const names = <String>[
      'High-Quality Amanita Mushroom',
      'High-Quality Ancient Mushroom',
      'High-Quality Arrow Mushroom',
      'High-Quality Bluffer Mushroom',
      'High-quality Chanterelle',
      'High-Quality Cloud Mushroom',
      'High-Quality Dictyophora',
      'High-Quality Dwarf Mushroom',
      'High-Quality Emperor Mushroom',
      'High-Quality Fortune Teller Mushroom',
      'High-Quality Garlic',
      'High-Quality Ghost Mushroom',
      'High-Quality Grape',
      'High-Quality Hot Pepper',
      'High-Quality Hump Mushroom',
      'High-quality Mesima',
      'High-quality Napa Cabbage',
      'High-Quality Olive',
      'High-Quality Onion',
      'High-Quality Paprika',
      'High-Quality Pumpkin',
      'High-quality Radish',
      'High-quality Red-spotted Amanita',
      'High-Quality Sky Mushroom',
      'High-Quality Strawberry',
      'High-Quality Sunflower',
      'High-Quality Tiger Mushroom',
      'High-Quality Tomato',
      'Special Chanterelle',
      'Special Dictyophora',
      'Special Fortune Teller Mushroom',
      'Special Garlic',
      'Special Grape',
      'Special Hot Pepper',
      'Special Mesima',
      'Special Napa Cabbage',
      'Special Olive',
      'Special Onion',
      'Special Paprika',
      'Special Pepper',
      'Special Pumpkin',
      'Special Radish',
      'Special Red-spotted Amanita',
      'Special Strawberry',
      'Special Sunflower',
      'Special Tomato',
    ];

    for (final name in names) {
      final purpose = recipeBookItemPurposeFor(
        name: name,
        recipe: null,
        currentKind: 'Recipe material',
        hasCraftUses: false,
      );
      expect(purpose.kind, 'Farming ingredient', reason: name);
      expect(
        purpose.description,
        'A higher-grade Farming product obtained through Farming or Plant Breeding.',
        reason: name,
      );
      expect(purpose.uses, <String>[
        'Used as a higher-grade ingredient in Cooking or Alchemy.',
      ], reason: name);
    }
  });

  test('verified terminal materials state their acquisition or exact use', () {
    const expectations = <String, (String, String)>{
      'Griffon Claw': ('Hunting material', 'Griffon Elixir'),
      'Monkey Blood': ('Alchemy blood', "Wise Man's Blood"),
      'Worm Blood': ('Alchemy blood', "Legendary Beast's Blood"),
      "Pilgrim's Cracked Stone": (
        'Guild drilling material',
        '1-2 Sharp Black Crystal Shards',
      ),
      "Pilgrim's Stone": (
        'Guild drilling material',
        '2-5 Sharp Black Crystal Shards',
      ),
      'Polished Opal': ('Processing material', 'Brilliant Opal'),
    };

    for (final entry in expectations.entries) {
      final purpose = recipeBookItemPurposeFor(
        name: entry.key,
        recipe: null,
        currentKind: 'Recipe material',
        hasCraftUses: false,
      );
      expect(purpose.kind, entry.value.$1, reason: entry.key);
      expect(
        <String>[purpose.description, ...purpose.uses].join(' '),
        contains(entry.value.$2),
        reason: entry.key,
      );
    }
  });

  test('selected materials provide concise acquisition guidance', () {
    final essence = curatedRecipeBookInfoForName('Essence of Dawn');
    final lightstone = curatedRecipeBookInfoForName(
      'Magical Lightstone Crystal',
    );
    final shard = curatedRecipeBookInfoForName('Magical Shard');

    expect(
      essence?.howToObtain,
      contains(
        "Heat eligible enhanced accessories with Dawn's Aura from an Old Moon Manager.",
      ),
    );
    expect(
      essence?.howToObtain.join(' '),
      allOf(contains('Black Shrine'), contains('Central Market')),
    );
    expect(
      lightstone?.howToObtain.single,
      contains('Exchange unwanted or Imperfect Lightstones with Dalishain'),
    );
    expect(
      shard?.howToObtain,
      contains(
        'Bulk: heat 10 Sealed Black Magic Crystals with 1 Black Stone Powder.',
      ),
    );
  });

  test('recipe uses put the crafted output before its recipes', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final recipes = catalog.processing.items;
    final dust = recipeBookInfoFor(
      name: 'Ancient Spirit Dust',
      recipe: recipes['Ancient Spirit Dust'],
      searchTerms: const <String>[],
      consumerRecipes:
          _consumers(recipes)['ancient spirit dust'] ?? const <Recipe>[],
    );

    expect(dust?.uses, isEmpty);
    expect(dust?.craftUses.single.output, 'Caphras Stone');
    expect(
      dust?.craftUses.single.formulas
          .map((formula) => formula.batchMultiplier)
          .toList(),
      const <int>[1, 10, 100],
    );
    final formula = dust?.craftUses.single.formulas.first;
    expect(formula?.method, 'Simple Alchemy');
    expect(
      formula?.ingredients
          .map((ingredient) => (ingredient.name, ingredient.quantity))
          .toList(),
      const <(String, double)>[('Ancient Spirit Dust', 5), ('Black Stone', 1)],
    );
  });

  test('opaque crafted outputs have short player-facing descriptions', () {
    final exalted = curatedRecipeBookInfoForName('Exalted Soul Fragment');

    expect(exalted, isNotNull);
    expect(exalted?.kind, 'Alchemy stone reform material');
    expect(
      recipeBookUseDescription(exalted!),
      'Upgrades a Blessed alchemy stone to Exalted and adds All Damage Reduction +2.',
    );
    expect(exalted.example, "Blessed Vell's Heart.");
  });

  test('terminal upgrade materials explain their real player-facing use', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final adhesive = recipeBookInfoFor(
      name: 'Adhesive for Upgrade',
      recipe: catalog.processing.items['Adhesive for Upgrade'],
      searchTerms: const <String>[],
      consumerRecipes: const <Recipe>[],
    );

    expect(
      adhesive?.uses.single,
      'Epheria ship upgrades: Sailboat → Caravel and Frigate → Galleass.',
    );
    expect(adhesive?.acquisitionFormulas, hasLength(2));
    expect(
      adhesive?.acquisitionFormulas.map((formula) => formula.method).toSet(),
      const <String>{'Heating'},
    );
    expect(adhesive?.howToObtain.first, startsWith('Heating:'));

    final expectedUses = <String, String>{
      'Blessed Soul Fragment':
          'Reforms a yellow-grade or better alchemy stone to Blessed.',
      'Flawless Magical Black Stone': 'Enhances Blackstar gear.',
      'Black Gem':
          'Enhances eligible Life Mastery clothes from +1 to +15 and Loggia Life accessories.',
      'Concentrated Magical Black Gem':
          'Enhances eligible Life Mastery clothes from PRI to PEN, Geranoa and Manos accessories, and Preonne accessories through DEC (X).',
      'Black Stone':
          'Enhances eligible weapons and defense gear through +15, and eligible Life Skill tools at their lower enhancement levels.',
      'Concentrated Magical Black Stone':
          'Enhances eligible weapons and defense gear from PRI to PEN.',
      'Memory Fragment': 'Restores maximum durability on most gear.',
      'Caphras Stone':
          'Inserted into eligible PEN boss gear for Caphras levels and Slumbering Origin progression.',
      'Sharp Black Crystal Shard':
          'Makes Concentrated Magical Black Stone, Concentrated Magical Black Gem, and several late-game materials.',
      'Primordial Black Stone': 'Enhances Sovereign weapons.',
      'Refined Essence of Emotions':
          'Removes and recovers a cup from a reformed accessory.',
      "Krogdalo's Origin Stone":
          'Courser Awakening attempts for a Dream Horse, such as Arduanatt.',
    };
    for (final entry in expectedUses.entries) {
      expect(
        curatedRecipeBookInfoForName(entry.key)?.uses,
        contains(entry.value),
        reason: entry.key,
      );
    }

    final blessed = recipeBookInfoFor(
      name: 'Blessed Soul Fragment',
      recipe: catalog.processing.items['Blessed Soul Fragment'],
      searchTerms: const <String>[],
      consumerRecipes: const <Recipe>[],
    );
    expect(blessed, isNotNull);
    expect(
      <String>[blessed!.summary, ...blessed.uses].join(' '),
      contains('to Blessed'),
      reason: 'Deduplication must not discard the resulting reform tier.',
    );
  });

  test('Obsidian Specter information explains the reform without duplication', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final recipe = catalog.processing.items["Obsidian Specter's Energy"];
    final info = recipeBookInfoFor(
      name: "Obsidian Specter's Energy",
      recipe: recipe,
      searchTerms: const <String>['sovereign', 'unrelated search metadata'],
      consumerRecipes: const <Recipe>[],
    );

    expect(info, isNotNull);
    expect(info?.kind, 'Blackstar armor reform material');
    expect(
      info?.summary,
      'A bound Elvia reform material for eligible Blackstar defense gear.',
    );
    expect(
      info?.uses,
      contains(
        'Reforms Blackstar defense gear into Obsidian Blackstar with 100% success.',
      ),
    );
    expect(info?.howToObtain.single, startsWith('Simple Alchemy:'));
    expect(
      info?.notes,
      contains('Cannot be registered on the Central Market.'),
    );
    expect(
      info?.notes,
      contains(
        'TET: Evasion +2 (+2), Damage Reduction +2 (+2), Max HP +40. PRI and PEN gain no extra Obsidian stats.',
      ),
    );
    expect(
      <String>[
        info!.summary,
        ...info.uses,
        ...info.howToObtain,
        ...info.notes,
      ].join(' ').toLowerCase(),
      isNot(contains('unrelated search metadata')),
    );
  });

  test('special progression families state a concrete player-facing use', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final expected = <String, String>{
      "Flawless Herald's Crystal": "Kabua's",
      'Brimming Essence of Aether': 'alchemy-stone',
      'Origin of Dark Hunger': 'Enhancement Chance',
      'Primordial Glow Crystal': 'Primordial Artina Sol',
      'Cup of Callous Sun': 'Critical Hit Extra Damage +3%',
      'Crystallized Energy of Endtimes': 'Amplified Lightstones',
      'Unstable Nouver Core': 'Nouverikant outfit',
    };

    for (final entry in expected.entries) {
      final recipe = _recipeAcrossCatalogs(
        entry.key,
        current: catalog.processing,
        catalogs: <ModeCatalog>[
          catalog.alchemy,
          catalog.cooking,
          catalog.processing,
        ],
      );
      final info = recipeBookInfoFor(
        name: entry.key,
        recipe: recipe,
        searchTerms: const <String>[],
        consumerRecipes: const <Recipe>[],
      );
      final text = <String>[
        info?.summary ?? '',
        ...?info?.effects,
        ...?info?.uses,
      ].join(' ');
      expect(text, contains(entry.value), reason: entry.key);
    }
  });

  test('removed armor-era enhancement materials are labelled as legacy', () {
    final expectedReplacements = <String, String>{
      'Black Stone (Armor)':
          'Removed from the current item system and replaced by Black Stone.',
      'Concentrated Magical Black Stone (Armor)':
          'Removed from the current item system and replaced by Concentrated Magical Black Stone.',
      'Hard Black Crystal Shard':
          'Removed from the current item system and replaced by Sharp Black Crystal Shard.',
    };

    for (final entry in expectedReplacements.entries) {
      final info = curatedRecipeBookInfoForName(entry.key);
      expect(info?.kind, 'Legacy enhancement material', reason: entry.key);
      expect(info?.summary, entry.value, reason: entry.key);
    }
  });

  test('Black Gem shows its direct enhancement use and crafting chain', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final recipes = catalog.processing.items;
    final consumers = _consumers(recipes);
    final info = recipeBookInfoFor(
      name: 'Black Gem',
      recipe: recipes['Black Gem'],
      searchTerms: const <String>[],
      consumerRecipes: consumers['black gem'] ?? const <Recipe>[],
    );

    expect(
      info?.uses,
      contains(
        'Enhances eligible Life Mastery clothes from +1 to +15 and Loggia Life accessories.',
      ),
    );
    expect(
      info?.summary,
      'A fixed-chance enhancement material for eligible Life Mastery equipment.',
    );
    expect(info?.craftUses.single.output, 'Concentrated Magical Black Gem');
  });

  test('name collisions never invent an item purpose or equipment type', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final catalogs = <ModeCatalog>[
      catalog.alchemy,
      catalog.cooking,
      catalog.processing,
    ];

    RecipeBookItemInfo? infoFor(String name) => recipeBookInfoFor(
      name: name,
      recipe: _recipeAcrossCatalogs(
        name,
        current: catalog.processing,
        catalogs: catalogs,
      ),
      searchTerms: const <String>[],
      consumerRecipes: const <Recipe>[],
    );

    final powder = infoFor('Black Stone Powder');
    expect(powder?.kind, 'Workshop and processing material');
    expect(
      powder?.summary,
      'A general-purpose material used in workshops and processing recipes.',
    );

    final blackGem = infoFor('Black Gem');
    expect(
      blackGem?.summary,
      'A fixed-chance enhancement material for eligible Life Mastery equipment.',
    );
    expect(blackGem?.summary, isNot(contains("matching enhancement system")));

    final concentrated = infoFor('Concentrated Magical Black Gem');
    expect(
      concentrated?.summary,
      startsWith('A higher-grade, fixed-chance enhancement material'),
    );
    expect(
      concentrated?.summary,
      isNot(contains("matching enhancement system")),
    );

    expect(infoFor('Elixir of Armor')?.kind, 'Elixir');
    expect(infoFor('Black Magic Crystal - Armor')?.kind, 'Gear crystal');

    final cottonseed = infoFor('Cottonseed Oil');
    expect(cottonseed?.summary.toLowerCase(), isNot(contains('farming seed')));

    final driedFish = infoFor('Dried Leather Carp');
    expect(
      driedFish?.summary.toLowerCase(),
      isNot(contains('textile or leather')),
    );

    final hardener = infoFor('Plywood Hardener');
    expect(
      hardener?.summary.toLowerCase(),
      isNot(contains('layered processed wood')),
    );

    final voidSeed = infoFor('Seed of Void');
    expect(voidSeed?.summary.toLowerCase(), isNot(contains('farming seed')));

    final roughRuby = infoFor('Rough Ruby');
    expect(
      roughRuby?.summary.toLowerCase(),
      isNot(contains('processed gemstone')),
    );

    final vinegar = infoFor('Vinegar');
    expect(vinegar?.kind, 'Cooking material');
    expect(
      vinegar?.summary.toLowerCase(),
      isNot(contains('temporary food effect')),
    );

    final alchemyBlood = infoFor("Clown's Blood");
    expect(alchemyBlood?.kind, 'Alchemy blood');
    expect(
      alchemyBlood?.summary,
      'A prepared alchemical blood used in advanced alchemy recipes.',
    );

    final treeKnot = infoFor('Bloody Tree Knot');
    expect(treeKnot?.summary.toLowerCase(), isNot(contains('animal blood')));

    final purified = infoFor('Purified Lightstone of Earth');
    expect(purified?.kind, 'Lightstone container');
    expect(
      purified?.uses,
      contains('Open it to obtain one random Earth Lightstone.'),
    );
    expect(
      purified?.uses.join(' ').toLowerCase(),
      isNot(contains('infuse it into an artifact')),
    );

    final ordinaryLightstone = infoFor('Lightstone of Earth: Boulder');
    expect(ordinaryLightstone?.kind, 'Lightstone');
    expect(
      ordinaryLightstone?.summary,
      'A Lightstone infused into an Artifact for its listed effect.',
    );

    final coral = infoFor('Coral Crystal');
    expect(coral?.kind, 'Crystal material');
    expect(
      coral?.uses.join(' ').toLowerCase(),
      isNot(contains('crystal preset')),
    );

    final ahKrad = infoFor("Crystal of Void - Ah'krad");
    expect(ahKrad?.kind, 'Gear crystal');
    expect(
      ahKrad?.summary,
      'A crystal equipped through a crystal preset for its listed effect.',
    );
    expect(
      ahKrad?.uses.join(' ').toLowerCase(),
      isNot(contains('crystal preset')),
      reason: 'The Description already explains how the crystal is equipped.',
    );

    final margoria = infoFor('Margoria Crystal');
    expect(margoria?.kind, 'Sea Crystal container');
    expect(margoria?.effectsTitle, 'Possible Sea Crystal Stats');
    expect(
      recipeBookUseDescription(margoria!),
      startsWith('Open it to receive a Margoria Sea Crystal'),
    );

    final reinforcedPlywood = infoFor('Sturdy Acacia Plywood');
    expect(
      reinforcedPlywood?.summary,
      'A reinforced plywood material made through Heating.',
    );
    expect(
      reinforcedPlywood?.summary.toLowerCase(),
      isNot(contains('chopping')),
    );
  });

  test('verified edge-case items use their real in-game role and effects', () {
    RecipeBookItemInfo? infoFor(String name) => recipeBookInfoFor(
      name: name,
      recipe: null,
      searchTerms: const <String>[],
      consumerRecipes: const <Recipe>[],
    );

    expect(infoFor("Ancient Guardian's Seal")?.kind, 'Necklace accessory');
    expect(infoFor("Gloves of Fortuna's Luck")?.kind, 'Defense gear');

    final cup = infoFor("Cup of Earth's Sorrows");
    expect(cup?.kind, 'Accessory reform material');
    expect(cup?.uses, contains(contains('All AP +3')));

    final magicalSeed = infoFor('Magical Napa Cabbage Seed');
    expect(magicalSeed?.kind, 'Plantable seed');
    expect(magicalSeed?.uses, contains(contains('5 grids')));

    final refinedJuice = infoFor('Refined Herbal Juice');
    expect(refinedJuice?.kind, 'Recovery consumable');
    expect(refinedJuice?.effects, contains('Recover 375 MP/WP/SP'));
    expect(refinedJuice?.effects.join(' '), isNot(contains('HP')));

    final remedy = infoFor('Elixir of Burn Removal');
    expect(remedy?.kind, 'Recovery consumable');
    expect(remedy?.effects, contains('Cures Burns'));
    expect(remedy?.notes, contains(contains('Cooldown: 30 sec.')));

    final spiritStone = infoFor('Guardian Spirit Stone');
    expect(spiritStone?.kind, 'Spirit stone');
    expect(
      spiritStone?.effects,
      containsAll(<String>[
        'All Damage Reduction +6',
        'All Evasion +8',
        'Max HP +110',
      ]),
    );

    final alchemyStone = infoFor('Splendid Alchemy Stone of Destruction');
    expect(alchemyStone?.kind, 'Alchemy stone');
    expect(alchemyStone?.effects, contains('All AP +13'));

    final heart = infoFor("Vell's Heart");
    expect(heart?.kind, "Vell's Heart");
    expect(heart?.effects, contains('All AP +8'));

    final beasts = infoFor("Beast's Draught");
    expect(beasts?.kind, 'Draught');
    expect(
      beasts?.effects,
      containsAll(<String>[
        'Extra AP Against Monsters +15',
        'Monster Damage Reduction Rate +10%',
      ]),
    );

    final thorn = infoFor('Elixir of Thorn');
    expect(thorn?.kind, 'Elixir');
    expect(thorn?.effects, contains('Target\'s HP -10 when struck'));
    expect(thorn?.notes, contains(contains('Duration: 10 min.')));

    final giants = infoFor("Giant's Draught");
    expect(giants?.kind, 'Draught');
    expect(
      giants?.effects,
      containsAll(<String>[
        'All AP +10',
        'All Special Attack Extra Damage +10%',
      ]),
    );
  });

  test('all named Artifacts show their exact built-in item effect', () {
    RecipeBookItemInfo? infoFor(String name) => recipeBookInfoFor(
      name: name,
      recipe: null,
      searchTerms: const <String>[],
      consumerRecipes: const <Recipe>[],
    );

    const expectedEffects = <String, String>{
      "Kehelle's Artifact - Black Spirit's Rage Max Increase":
          "Black Spirit's Rage Max Increase +10%",
      "Kehelle's Artifact - Max HP": 'Max HP +75',
      "Kehelle's Artifact - Max Stamina": 'Max Stamina +50',
      "Lesha's Artifact - All Damage Reduction": 'All Damage Reduction +3',
      "Lesha's Artifact - All Evasion": 'All Evasion +6',
      "Lesha's Artifact - Magic Damage Reduction": 'Magic Damage Reduction +6',
      "Lesha's Artifact - Magic Evasion": 'Magic Evasion +12',
      "Lesha's Artifact - Melee Damage Reduction": 'Melee Damage Reduction +6',
      "Lesha's Artifact - Melee Evasion": 'Melee Evasion +12',
      "Lesha's Artifact - Monster Damage Reduction":
          'Monster Damage Reduction +9',
      "Lesha's Artifact - Ranged Damage Reduction":
          'Ranged Damage Reduction +6',
      "Lesha's Artifact - Ranged Evasion": 'Ranged Evasion +12',
      "Marsh's Artifact - Extra AP Against Monsters":
          'Extra AP Against Monsters +6',
      "Marsh's Artifact - Magic Accuracy": 'Magic Accuracy +8',
      "Marsh's Artifact - Magic AP": 'Magic AP +4',
      "Marsh's Artifact - Melee Accuracy": 'Melee Accuracy +8',
      "Marsh's Artifact - Melee AP": 'Melee AP +4',
      "Marsh's Artifact - Ranged Accuracy": 'Ranged Accuracy +8',
      "Marsh's Artifact - Ranged AP": 'Ranged AP +4',
      "Sethra's Artifact - Alchemy EXP": 'Alchemy EXP +5%',
      "Sethra's Artifact - Alchemy Mastery": 'Alchemy Mastery +10',
      "Sethra's Artifact - Barter EXP": 'Barter EXP +5%',
      "Sethra's Artifact - Cooking EXP": 'Cooking EXP +5%',
      "Sethra's Artifact - Cooking Mastery": 'Cooking Mastery +10',
      "Sethra's Artifact - Farming EXP": 'Farming EXP +5%',
      "Sethra's Artifact - Fishing EXP": 'Fishing EXP +5%',
      "Sethra's Artifact - Fishing Mastery": 'Fishing Mastery +10',
      "Sethra's Artifact - Gathering EXP": 'Gathering EXP +5%',
      "Sethra's Artifact - Gathering Item Drop Rate":
          'Gathering Item Drop Rate +2%',
      "Sethra's Artifact - Gathering Mastery": 'Gathering Mastery +10',
      "Sethra's Artifact - Hunting EXP": 'Hunting EXP +5%',
      "Sethra's Artifact - Hunting Mastery": 'Hunting Mastery +10',
      "Sethra's Artifact - Life EXP": 'Life EXP +3%',
      "Sethra's Artifact - Life Skill Mastery": 'Life Skill Mastery +7',
      "Sethra's Artifact - Mount EXP": 'Mount EXP +3%',
      "Sethra's Artifact - Processing EXP": 'Processing EXP +5%',
      "Sethra's Artifact - Processing Mastery": 'Processing Mastery +10',
      "Sethra's Artifact - Processing Success Rate":
          'Processing Success Rate +5%',
      "Sethra's Artifact - Sailing EXP": 'Sailing EXP +5%',
      "Sethra's Artifact - Sailing Mastery": 'Sailing Mastery +10',
      "Sethra's Artifact - Trading EXP": 'Trading EXP +5%',
      "Sethra's Artifact - Training EXP": 'Training EXP +5%',
      "Sethra's Artifact - Training Mastery": 'Training Mastery +10',
    };

    for (final entry in expectedEffects.entries) {
      final info = infoFor(entry.key);
      expect(info?.kind, 'Artifact', reason: entry.key);
      expect(info?.effects, <String>[entry.value], reason: entry.key);
    }
  });

  test('combined Vell and Khan stones show heart and timed effects', () {
    RecipeBookItemInfo? infoFor(String name) => recipeBookInfoFor(
      name: name,
      recipe: null,
      searchTerms: const <String>[],
      consumerRecipes: const <Recipe>[],
    );

    const gradeEffects = <String, Map<String, List<String>>>{
      'Resplendent': <String, List<String>>{
        'Destruction': <String>[
          'All AP +10',
          'All Accuracy +12',
          'Attack Speed +6%',
          'Casting Speed +6%',
        ],
        'Life': <String>[
          'Alchemy/Cooking Time -1.7 sec',
          'Processing Success Rate +17%',
          'Weight Limit +90 LT',
          'Gathering/Fishing Speed +2',
          'Gathering Item Drop Rate +16%',
        ],
        'Protection': <String>[
          'All Damage Reduction +10',
          'All Evasion +12',
          'Max HP +170',
          'All Resistance +6%',
        ],
      },
      'Splendid': <String, List<String>>{
        'Destruction': <String>[
          'All AP +13',
          'All Accuracy +14',
          'Attack Speed +8%',
          'Casting Speed +8%',
        ],
        'Life': <String>[
          'Alchemy/Cooking Time -2 sec',
          'Processing Success Rate +20%',
          'Weight Limit +105 LT',
          'Gathering/Fishing Speed +3',
          'Gathering Item Drop Rate +20%',
        ],
        'Protection': <String>[
          'All Damage Reduction +13',
          'All Evasion +14',
          'Max HP +210',
          'All Resistance +7%',
        ],
      },
      'Shining': <String, List<String>>{
        'Destruction': <String>[
          'All AP +16',
          'All Accuracy +16',
          'Attack Speed +10%',
          'Casting Speed +10%',
        ],
        'Life': <String>[
          'Alchemy/Cooking Time -2.5 sec',
          'Processing Success Rate +25%',
          'Weight Limit +120 LT',
          'Gathering/Fishing Speed +3',
          'Gathering Item Drop Rate +25%',
        ],
        'Protection': <String>[
          'All Damage Reduction +16',
          'All Evasion +16',
          'Max HP +250',
          'All Resistance +8%',
        ],
      },
    };

    for (final grade in gradeEffects.entries) {
      final vell = infoFor("${grade.key} Vell's Heart");
      expect(vell?.effects.first, 'Displayed AP +3 (while equipped)');
      expect(
        vell?.effects,
        containsAll(grade.value['Destruction']!),
        reason: "${grade.key} Vell's Heart",
      );
      expect(vell?.notes, contains(contains('Duration: 5 min.')));

      for (final role in grade.value.entries) {
        final khan = infoFor("${grade.key} Khan's Heart: ${role.key}");
        final equippedEffect = switch (role.key) {
          'Destruction' => 'Displayed AP +2 (while equipped)',
          'Protection' => 'Displayed DP +2 (while equipped)',
          _ => 'All Life Skill Mastery +25 (while equipped)',
        };
        expect(khan?.effects.first, equippedEffect);
        expect(
          khan?.effects,
          containsAll(<String>[
            if (role.key == 'Life') 'Life EXP +30%',
            ...role.value,
          ]),
          reason: "${grade.key} Khan's Heart: ${role.key}",
        );
        expect(
          khan?.notes,
          contains(
            contains(
              role.key == 'Life' ? 'Duration: 10 min.' : 'Duration: 5 min.',
            ),
          ),
        );
      }
    }
  });

  test('simple materials stay compact and show their direct recipe chain', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final recipes = catalog.processing.items;
    final consumers = _consumers(recipes);
    final plank = recipeBookInfoFor(
      name: 'Ash Plank',
      recipe: recipes['Ash Plank'],
      searchTerms: const <String>[],
      consumerRecipes: consumers['ash plank'] ?? const <Recipe>[],
    );

    expect(plank?.kind, 'Wood material');
    expect(plank?.summary, 'Processed wood made by chopping timber.');
    expect(plank?.effects, isEmpty);
    expect(plank?.howToObtain, const <String>['Chopping: 5 Ash Timber.']);
    expect(plank?.craftUses.single.output, 'Ash Plywood');
    expect(plank?.craftUses.single.recipes.single, 'Chopping: 10 Ash Plank.');
    expect(
      recipeBookUseDescription(plank!),
      'Processed wood made by chopping timber.',
    );
  });

  test(
    'structured formulas retain every route, batch, and substitute ratio',
    () {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      RecipeBookItemInfo infoFor(String name, Map<String, Recipe> recipes) {
        return recipeBookInfoFor(
          name: name,
          recipe: recipes[name],
          searchTerms: const <String>[],
          consumerRecipes: const <Recipe>[],
        )!;
      }

      final perfume = infoFor('Perfume of Verdure', catalog.alchemy.items);
      expect(perfume.acquisitionFormulas, hasLength(2));
      expect(
        perfume.acquisitionFormulas
            .map(
              (formula) => (formula.routeLabel, formula.method, formula.type),
            )
            .toList(),
        const <(String?, String, String)>[
          ('Alchemy Tool', 'Alchemy Tool (Skilled 1+)', 'alchemy'),
          ('Simple Alchemy', 'Simple Alchemy', 'simple_alchemy'),
        ],
      );

      final causality = infoFor(
        'Causality Shardstone - Earring',
        catalog.processing.items,
      );
      expect(
        causality.acquisitionFormulas
            .map((formula) => formula.batchMultiplier)
            .toList(),
        const <int>[1, 10],
      );
      expect(
        causality.acquisitionFormulas.last.ingredients
            .map((ingredient) => (ingredient.name, ingredient.quantity))
            .toList(),
        const <(String, double)>[
          ('Twilight of the End - Earring', 50),
          ('Caphras Stone', 100),
          ('Magical Shard', 100),
          ('Essence of Dawn', 100),
          ('Black Stone Powder', 1),
        ],
      );

      final viridian = infoFor('Viridian Draught', catalog.alchemy.items);
      final mastery = viridian.acquisitionFormulas.single.ingredients.first;
      expect(mastery.options, contains('Elixir of Improved Mastery'));
      expect(
        mastery.substituteRatios['Elixir of Improved Mastery'],
        closeTo(1 / 3, 1e-9),
      );
      expect(
        mastery.quantity *
            mastery.substituteRatios['Elixir of Improved Mastery']!,
        1,
      );

      final reformed = infoFor(
        'Dawnbound Ekleta Necklace',
        catalog.processing.items,
      );
      expect(reformed.acquisitionFormulas, hasLength(1));
      expect(
        reformed.acquisitionFormulas.single.ingredients
            .map((ingredient) => (ingredient.name, ingredient.quantity))
            .toList(),
        const <(String, double)>[
          ('Ekleta Necklace', 1),
          ('Cup of Destined Dawn', 1),
        ],
      );

      final polished = withEstimatedRecipeBookOutputs(
        infoFor('Polished Marble', catalog.processing.items),
        const <String>['Polished Marble'],
      );
      expect(polished.acquisitionFormulas.single.outputEstimated, isTrue);
      expect(
        causality.acquisitionFormulas.every(
          (formula) => !formula.outputEstimated,
        ),
        isTrue,
      );
      expect(
        causality.uses,
        isEmpty,
        reason: 'The description already explains the enhancement use.',
      );

      final researchedReform = withResearchedAcquisition(reformed, const <
        String
      >[
        'Reform Ekleta Necklace with Cup of Destined Dawn to gain Max HP +300. '
            'Extract with Refined Essence of Emotions to recover the original '
            'accessory and cup.',
      ]);
      expect(
        researchedReform.acquisitionNotes,
        isEmpty,
        reason: 'The structured recipe and Notes already contain both facts.',
      );
      expect(
        researchedReform.notes,
        contains(
          'Extract with Refined Essence of Emotions to recover the original '
          'accessory and cup.',
        ),
      );

      final uniqueRoute = withResearchedAcquisition(reformed, const <String>[
        'Speak with the Ynix Remnant after completing the prerequisite quest. '
            'Extract with Refined Essence of Emotions to recover the original '
            'accessory and cup.',
      ]);
      expect(uniqueRoute.acquisitionNotes, <String>[
        'Speak with the Ynix Remnant after completing the prerequisite quest.',
      ]);
    },
  );

  test('food, recovery, and worker consumables show exact effects', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final examples = <String, List<String>>{
      'Aloe Cookie': <String>['All Accuracy +4'],
      'Beer': <String>['Recover 2 Worker Stamina'],
      'Carrot Confit': <String>[
        'Recover 12,500 Mount Stamina',
        'Recover 5,500 Mount HP',
      ],
      'Citron Tea': <String>['Cures Frostbite'],
    };

    for (final entry in examples.entries) {
      final recipe = _recipeAcrossCatalogs(
        entry.key,
        current: catalog.cooking,
        catalogs: <ModeCatalog>[
          catalog.alchemy,
          catalog.cooking,
          catalog.processing,
        ],
      );
      final info = recipeBookInfoFor(
        name: entry.key,
        recipe: recipe,
        searchTerms: const <String>[],
        consumerRecipes: const <Recipe>[],
      );

      expect(info, isNotNull, reason: entry.key);
      expect(info?.summary.trim(), isNotEmpty, reason: entry.key);
      expect(info?.effects, entry.value, reason: entry.key);
      expect(
        <String>[
          info!.summary,
          ...info.effects,
          ...info.notes,
        ].join(' ').toLowerCase(),
        isNot(contains('usage effect')),
        reason: entry.key,
      );
    }
  });

  test('ingredient-only items still get short output-first hover info', () {
    final consumer = Recipe(
      name: 'Ash Plank',
      type: 'processing',
      baseOutput: 1,
      group: 'Processing - Chopping',
      method: 'Chopping',
      ingredients: <Ingredient>[
        Ingredient(
          name: 'Ash Timber',
          quantity: 5,
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
      outputMinimum: null,
      outputMaximum: null,
    );
    final timber = recipeBookInfoFor(
      name: 'Ash Timber',
      recipe: null,
      searchTerms: const <String>[],
      consumerRecipes: <Recipe>[consumer],
    );

    expect(timber?.kind, 'Wood material');
    expect(timber?.summary, 'Raw wood that can be processed into planks.');
    expect(timber?.craftUses.single.output, 'Ash Plank');
    expect(timber?.craftUses.single.recipes.single, 'Chopping: 5 Ash Timber.');
  });

  test(
    'reference-only recipes do not leak into primary acquisition or uses',
    () {
      final manual = _roleRecipe(
        'Manual Recovery',
        role: RecipeRole.manualConversion,
        ingredientName: 'Reference Material',
      );
      final salvage = _roleRecipe(
        'Salvage Recovery',
        role: RecipeRole.salvage,
        ingredientName: 'Reference Material',
      );
      final source = _roleRecipe(
        'Reference Material',
        role: RecipeRole.manualConversion,
        ingredientName: 'Expensive Finished Item',
      );

      final info = recipeBookInfoFor(
        name: 'Reference Material',
        recipe: source,
        searchTerms: const <String>[],
        consumerRecipes: <Recipe>[manual, salvage],
      );

      expect(info, isNotNull);
      expect(info?.howToObtain, isEmpty);
      expect(info?.craftUses, isEmpty);
    },
  );

  test('effect-item copy adds a short definition and avoids long prose', () {
    final lightstone = recipeBookInfoFor(
      name: 'Amplified Lightstone of Earth: Boulder',
      recipe: null,
      searchTerms: const <String>[],
      consumerRecipes: const <Recipe>[],
    );
    final draught = recipeBookInfoFor(
      name: 'Harmony Draught - Edania',
      recipe: null,
      searchTerms: const <String>[],
      consumerRecipes: const <Recipe>[],
    );

    expect(
      lightstone?.summary,
      'A Lightstone infused into an Artifact for its listed effect.',
    );
    expect(lightstone?.effects, contains('Knockdown/Bound Resistance +4%'));
    expect(
      lightstone?.uses,
      containsAll(<String>[
        'Exchange 3 unwanted Lightstones with Dalishain for 1 Purified Lightstone.',
        'Exchange it with Dalishain for Magical Lightstone Crystals.',
      ]),
    );
    expect(
      lightstone?.uses,
      isNot(
        contains('Infuse it into an Artifact to apply the listed stat effect.'),
      ),
      reason: 'The Description already explains how the Lightstone is used.',
    );
    expect(draught?.summary, 'A temporary combat draught.');
    expect(draught?.effects, contains('All AP +13'));
  });

  test('every icon-reachable production item has useful hover info', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final catalogs = <ModeCatalog>[
      catalog.alchemy,
      catalog.cooking,
      catalog.processing,
    ];
    final failures = <String>[];

    for (final catalogPart in catalogs) {
      final consumers = _consumers(catalogPart.items);
      final candidates = _iconCandidates(catalogPart.items);
      for (final candidate in candidates.values) {
        if (candidate.name.trim().isEmpty) {
          failures.add(
            '${catalogPart.mode.name}: blank name [${candidate.sources.join(', ')}]',
          );
          continue;
        }
        final recipe = _recipeAcrossCatalogs(
          candidate.name,
          current: catalogPart,
          catalogs: catalogs,
        );
        final info = recipeBookInfoFor(
          name: candidate.name,
          recipe: recipe,
          searchTerms: const <String>[],
          consumerRecipes: consumers[_fold(candidate.name)] ?? const <Recipe>[],
        );
        if (info == null ||
            !info.hasBody ||
            info.title.trim().isEmpty ||
            info.kind.trim().isEmpty) {
          failures.add(
            '${catalogPart.mode.name}: ${candidate.name} '
            '[${candidate.sources.join(', ')}]',
          );
        }
      }
    }

    expect(failures, isEmpty);
  });

  test('every production item has hover info and effect data stays exact', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final failures = <String>[];

    for (final catalogPart in <ModeCatalog>[
      catalog.alchemy,
      catalog.cooking,
      catalog.processing,
    ]) {
      final consumers = _consumers(catalogPart.items);
      for (final entry in catalogPart.items.entries) {
        final name = entry.key;
        final recipe = entry.value;
        final info = recipeBookInfoFor(
          name: name,
          recipe: recipe,
          searchTerms: <String>[?catalogPart.searchAliases[name]],
          consumerRecipes: consumers[_fold(name)] ?? const <Recipe>[],
        );
        if (info == null || !info.hasBody) {
          failures.add('${catalogPart.mode.name}: $name');
        } else if (info.title.trim().isEmpty || info.kind.trim().isEmpty) {
          failures.add('${catalogPart.mode.name}: $name has no card header');
        } else if (<String>[
          info.summary,
          ...info.uses,
          ...info.notes,
        ].join(' ').toLowerCase().contains('related to:')) {
          failures.add('${catalogPart.mode.name}: $name leaks search metadata');
        } else if (_isBuffRecipe(name, recipe)) {
          if (info.effects.isEmpty ||
              info.effects.any((effect) => effect.startsWith('Buff focus:'))) {
            failures.add('${catalogPart.mode.name}: $name has no exact buffs');
          }
        } else if (_isCrystalRecipe(name, recipe)) {
          if (info.effects.any(
            (effect) =>
                effect.startsWith('Crystal focus:') ||
                effect.startsWith('Lightstone focus:') ||
                effect.startsWith('Material focus:'),
          )) {
            failures.add(
              '${catalogPart.mode.name}: $name has placeholder crystal info',
            );
          }
          if (info.uses.any((use) => use.length > 140)) {
            failures.add(
              '${catalogPart.mode.name}: $name has an overlong usage line',
            );
          }
        }
      }
    }

    expect(failures, isEmpty);
  });
}

bool _isBuffRecipe(String name, Recipe recipe) {
  final foldedName = _fold(name);
  final foldedGroup = _fold(recipe.group ?? '');
  if (foldedGroup.contains('elixir') ||
      foldedGroup.contains('perfume') ||
      foldedGroup.contains('draught')) {
    return true;
  }
  return foldedName.contains('elixir') ||
      foldedName.contains('draught') ||
      foldedName.contains('perfume') ||
      foldedName.startsWith('immortal: ') ||
      foldedName.startsWith('blessing of mystic beasts');
}

bool _isCrystalRecipe(String name, Recipe recipe) {
  final foldedName = _fold(name);
  final foldedGroup = _fold(recipe.group ?? '');
  if (foldedGroup.contains('crystal') || foldedGroup.contains('lightstone')) {
    return true;
  }
  const signals = <String>[
    'crystal',
    'lightstone',
    'girin',
    'bonghwang',
    'haetae',
    "ah'krad",
    'olucas',
    'elkarr',
    'hoom',
    'gervish',
    'macalod',
  ];
  return signals.any(foldedName.contains);
}

Map<String, List<Recipe>> _consumers(Map<String, Recipe> recipes) {
  final result = <String, List<Recipe>>{};
  for (final recipe in recipes.values) {
    for (final ingredient in recipe.ingredients) {
      for (final referenced in <String>{
        ingredient.name,
        ...ingredient.options,
        ...ingredient.substituteRatios.keys,
      }) {
        result.putIfAbsent(_fold(referenced), () => <Recipe>[]).add(recipe);
      }
    }
  }
  return result;
}

Map<String, _InfoCandidate> _iconCandidates(Map<String, Recipe> recipes) {
  final result = <String, _InfoCandidate>{};

  void add(String name, String source) {
    final folded = _fold(name);
    final existing = result[folded];
    if (existing != null) {
      existing.sources.add(source);
      return;
    }
    result[folded] = _InfoCandidate(name, <String>{source});
  }

  for (final entry in recipes.entries) {
    add(entry.key, 'output');
    for (final ingredient in entry.value.ingredients) {
      add(ingredient.name, 'ingredient');
      for (final option in ingredient.options) {
        add(option, 'option');
      }
      for (final substitute in ingredient.substituteRatios.keys) {
        add(substitute, 'ratio');
      }
    }
  }
  return result;
}

Recipe? _recipeAcrossCatalogs(
  String name, {
  required ModeCatalog current,
  required List<ModeCatalog> catalogs,
}) {
  Recipe? findIn(ModeCatalog catalog) {
    for (final entry in catalog.items.entries) {
      if (_fold(entry.key) == _fold(name)) return entry.value;
    }
    return null;
  }

  final local = findIn(current);
  if (local != null) return local;
  for (final catalog in catalogs) {
    if (catalog.mode == current.mode) continue;
    final recipe = findIn(catalog);
    if (recipe != null) return recipe;
  }
  return null;
}

final class _InfoCandidate {
  _InfoCandidate(this.name, this.sources);

  final String name;
  final Set<String> sources;
}

String _fold(String value) => value.trim().toLowerCase();

Recipe _roleRecipe(
  String name, {
  required RecipeRole role,
  required String ingredientName,
}) => Recipe(
  name: name,
  type: 'processing',
  baseOutput: 1,
  group: 'Reference',
  method: 'Heating',
  ingredients: <Ingredient>[
    Ingredient(
      name: ingredientName,
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
