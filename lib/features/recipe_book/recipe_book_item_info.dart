import '../../domain/models/catalog_models.dart';
import '../../domain/state/user_source_notes.dart';
import 'recipe_book_exact_buff_info.dart';
import 'recipe_book_exact_crystal_info.dart';
import 'recipe_book_exact_food_info.dart';
import 'recipe_book_item_purpose.dart';

final class RecipeBookCraftUse {
  const RecipeBookCraftUse({
    required this.output,
    this.formulas = const <RecipeBookFormula>[],
  });

  final String output;
  final List<RecipeBookFormula> formulas;

  /// Compact compatibility view for non-visual audits and older callers.
  List<String> get recipes =>
      List<String>.unmodifiable(formulas.map(recipeBookFormulaSummary));

  RecipeBookCraftUse copyWith({
    String? output,
    List<RecipeBookFormula>? formulas,
  }) => RecipeBookCraftUse(
    output: output ?? this.output,
    formulas: formulas ?? this.formulas,
  );
}

bool isBrowsableRecipeBookReference(Recipe recipe) {
  final group = recipe.group?.trim().toLowerCase() ?? '';
  return recipe.isManualConversion && group.startsWith('reference - ');
}

/// One complete, display-ready production route.
///
/// Formula mechanics stay structured all the way to the Recipe Book so the UI
/// can show one material per row instead of rebuilding a dense sentence.
final class RecipeBookFormula {
  const RecipeBookFormula({
    required this.outputName,
    required this.type,
    required this.method,
    required this.baseOutput,
    required this.ingredients,
    this.variantId,
    this.routeId,
    this.routeLabel,
    this.batchMultiplier = 1,
    this.outputMinimum,
    this.outputMaximum,
    this.outputEstimated = false,
  });

  final String outputName;
  final String type;
  final String method;
  final String? variantId;
  final String? routeId;
  final String? routeLabel;
  final int batchMultiplier;
  final double baseOutput;
  final double? outputMinimum;
  final double? outputMaximum;
  final bool outputEstimated;
  final List<Ingredient> ingredients;

  RecipeBookFormula copyWith({bool? outputEstimated}) => RecipeBookFormula(
    outputName: outputName,
    type: type,
    method: method,
    variantId: variantId,
    routeId: routeId,
    routeLabel: routeLabel,
    batchMultiplier: batchMultiplier,
    baseOutput: baseOutput,
    outputMinimum: outputMinimum,
    outputMaximum: outputMaximum,
    outputEstimated: outputEstimated ?? this.outputEstimated,
    ingredients: ingredients,
  );
}

final class RecipeBookItemInfo {
  const RecipeBookItemInfo({
    required this.title,
    required this.kind,
    required this.summary,
    this.effectsTitle = 'Effects',
    this.effects = const <String>[],
    this.uses = const <String>[],
    this.craftUses = const <RecipeBookCraftUse>[],
    this.acquisitionFormulas = const <RecipeBookFormula>[],
    List<String> howToObtain = const <String>[],
    List<String>? acquisitionNotes,
    this.example,
    this.notes = const <String>[],
  }) : acquisitionNotes = acquisitionNotes ?? howToObtain;

  final String title;
  final String kind;
  final String summary;
  final String effectsTitle;
  final List<String> effects;
  final List<String> uses;
  final List<RecipeBookCraftUse> craftUses;
  final List<RecipeBookFormula> acquisitionFormulas;
  final List<String> acquisitionNotes;
  final String? example;
  final List<String> notes;

  /// Compatibility view used by the Planner's separate acquisition popover.
  /// The Recipe Book itself renders [acquisitionFormulas] structurally.
  List<String> get howToObtain => List<String>.unmodifiable(<String>[
    ...acquisitionFormulas.map(recipeBookFormulaSummary),
    ...acquisitionNotes,
  ]);

  bool get hasBody =>
      summary.trim().isNotEmpty ||
      effects.isNotEmpty ||
      uses.isNotEmpty ||
      craftUses.isNotEmpty ||
      acquisitionFormulas.isNotEmpty ||
      acquisitionNotes.isNotEmpty ||
      (example?.trim().isNotEmpty ?? false) ||
      notes.isNotEmpty ||
      // A neutral category is still useful for a deliberately terse card.
      // This keeps unknown items inspectable without inventing a description.
      kind.trim().isNotEmpty;

  RecipeBookItemInfo copyWith({
    String? title,
    String? kind,
    String? summary,
    String? effectsTitle,
    List<String>? effects,
    List<String>? uses,
    List<RecipeBookCraftUse>? craftUses,
    List<RecipeBookFormula>? acquisitionFormulas,
    List<String>? acquisitionNotes,
    String? example,
    List<String>? notes,
  }) => RecipeBookItemInfo(
    title: title ?? this.title,
    kind: kind ?? this.kind,
    summary: summary ?? this.summary,
    effectsTitle: effectsTitle ?? this.effectsTitle,
    effects: effects ?? this.effects,
    uses: uses ?? this.uses,
    craftUses: craftUses ?? this.craftUses,
    acquisitionFormulas: acquisitionFormulas ?? this.acquisitionFormulas,
    acquisitionNotes: acquisitionNotes ?? this.acquisitionNotes,
    example: example ?? this.example,
    notes: notes ?? this.notes,
  );
}

RecipeBookItemInfo withEstimatedRecipeBookOutputs(
  RecipeBookItemInfo info,
  Iterable<String> outputNames,
) {
  final estimatedNames = outputNames.map(_fold).toSet();
  if (estimatedNames.isEmpty) return info;

  RecipeBookFormula mark(RecipeBookFormula formula) =>
      estimatedNames.contains(_fold(formula.outputName)) &&
          !formula.outputEstimated
      ? formula.copyWith(outputEstimated: true)
      : formula;

  final acquisitionFormulas = info.acquisitionFormulas
      .map(mark)
      .toList(growable: false);
  final craftUses = info.craftUses
      .map(
        (use) => use.copyWith(
          formulas: use.formulas.map(mark).toList(growable: false),
        ),
      )
      .toList(growable: false);
  return info.copyWith(
    acquisitionFormulas: List<RecipeBookFormula>.unmodifiable(
      acquisitionFormulas,
    ),
    craftUses: List<RecipeBookCraftUse>.unmodifiable(craftUses),
  );
}

RecipeBookItemInfo withResearchedAcquisition(
  RecipeBookItemInfo info,
  Iterable<String> researchedRoutes,
) {
  final existingReferences = <String>[
    info.summary,
    ...info.effects,
    ...info.uses,
    ...info.acquisitionFormulas.map(recipeBookFormulaSummary),
    ...info.notes,
  ];
  final routes = _uniqueInformationSentences(<String>[
    ...info.acquisitionNotes,
    ...researchedRoutes,
  ], coveredBy: existingReferences);
  if (_sameLines(routes, info.acquisitionNotes)) return info;
  return info.copyWith(acquisitionNotes: List<String>.unmodifiable(routes));
}

String recipeBookUseDescription(RecipeBookItemInfo info) {
  final summary = info.summary.trim();
  if (summary.isNotEmpty) return summary;

  final kind = info.kind.trim().toLowerCase();
  if (kind == 'sea crystal container' && info.uses.isNotEmpty) {
    return info.uses.first;
  }
  if (info.effects.isNotEmpty) {
    final effect = info.effects.first;
    return switch (kind) {
      'draught' => 'Temporary draught buff; one effect is $effect.',
      'elixir' => 'Temporary elixir buff; one effect is $effect.',
      'perfume' => 'Temporary perfume buff; one effect is $effect.',
      'blessing' => 'Temporary residence-style buff; effect: $effect.',
      'lightstone' => 'Lightstone for artifacts; effect: $effect.',
      'gear crystal' => 'Socketable gear crystal; effect: $effect.',
      _ => 'Effect: $effect.',
    };
  }
  if (info.uses.isNotEmpty) return info.uses.first;
  if (info.craftUses.isNotEmpty) {
    return 'Used to make ${info.craftUses.first.output}.';
  }
  // An item category is not enough evidence to explain what the item does.
  // Keep this blank when no verified effect, use, recipe destination, or
  // curated summary exists instead of manufacturing plausible-sounding copy.
  return '';
}

RecipeBookItemInfo? curatedRecipeBookInfoForName(String name) =>
    _curatedInfo[_fold(name)];

RecipeBookItemInfo? recipeBookInfoFor({
  required String name,
  required Recipe? recipe,
  required Iterable<String> searchTerms,
  required Iterable<Recipe> consumerRecipes,
}) {
  // Search aliases help users find items, but they are not authoritative
  // gameplay facts and must never become item-description copy.
  final _ = searchTerms;
  final foldedName = _fold(name);
  final consumers = _distinctConsumers(consumerRecipes, name);
  final exactBuff = exactBuffInfoByName[foldedName];
  if (exactBuff != null) {
    return _finishItemInfo(
      _exactBuffHoverInfo(
        exactBuff,
        foldedName,
        recipe: recipe,
        consumers: consumers,
      ),
      name: name,
      recipe: recipe,
      consumers: consumers,
    );
  }

  final exactFood = exactFoodInfoByName[foldedName];
  if (exactFood != null) {
    return _finishItemInfo(
      _exactFoodHoverInfo(exactFood, recipe: recipe, consumers: consumers),
      name: name,
      recipe: recipe,
      consumers: consumers,
    );
  }

  final curated = curatedRecipeBookInfoForName(name);
  if (curated != null) {
    return _finishItemInfo(
      _completeCuratedInfo(curated, recipe: recipe, consumers: consumers),
      name: name,
      recipe: recipe,
      consumers: consumers,
    );
  }

  final qualityBase = recipe?.qualityBase;
  if (qualityBase != null && qualityBase.trim().isNotEmpty) {
    final baseInfo = _curatedInfo[_fold(qualityBase)];
    if (baseInfo != null) {
      return _finishItemInfo(
        _variantInfo(
          title: name,
          baseInfo: baseInfo,
          note: 'Higher-grade version of ${baseInfo.title}.',
        ),
        name: name,
        recipe: recipe,
        consumers: consumers,
      );
    }
  }

  if (foldedName.startsWith('immortal: ')) {
    final immortalBase =
        _curatedInfo[foldedName.substring('immortal: '.length)];
    if (immortalBase != null) {
      return _finishItemInfo(
        _variantInfo(
          title: name,
          baseInfo: immortalBase,
          note: 'Immortal version: effects persist if you die.',
        ),
        name: name,
        recipe: recipe,
        consumers: consumers,
      );
    }
  }

  final exactCrystal = exactCrystalInfoByName[foldedName];
  if (exactCrystal != null) {
    return _finishItemInfo(
      _exactCrystalHoverInfo(
        exactCrystal,
        foldedName: foldedName,
        consumers: consumers,
        recipe: recipe,
      ),
      name: name,
      recipe: recipe,
      consumers: consumers,
    );
  }

  return _finishItemInfo(
    _compactItemInfo(name: name, recipe: recipe, consumers: consumers),
    name: name,
    recipe: recipe,
    consumers: consumers,
  );
}

final Map<String, RecipeBookItemInfo>
_curatedInfo = <String, RecipeBookItemInfo>{
  'adaptation draught': _buffInfo(
    title: 'Adaptation Draught',
    kind: 'Draught',
    summary: 'Defensive draught for survivability.',
    effects: <String>[
      'All Damage Reduction +13',
      'All Evasion +13',
      'Max HP +200',
      'Max Stamina +200',
    ],
    duration: '15 min',
    cooldown: '10 sec',
    stackNote: 'Only the last draught effect applies.',
  ),
  'fury draught': _buffInfo(
    title: 'Fury Draught',
    kind: 'Draught',
    summary: 'Offensive draught for AP, accuracy, and special attack damage.',
    effects: <String>[
      'All AP +13',
      'All Accuracy +13',
      'All Special Attack Extra Damage +2%',
    ],
    duration: '15 min',
    cooldown: '10 sec',
    stackNote: 'Only the last draught effect applies.',
  ),
  'harmony draught': _buffInfo(
    title: 'Harmony Draught',
    kind: 'Draught',
    summary:
        'Combined offensive and defensive draught used as the base for Harmony variants.',
    effects: <String>[
      'All AP +13',
      'All Accuracy +13',
      'All Damage Reduction +13',
      'All Evasion +13',
      'Max HP +200',
      'Max Stamina +200',
      'Movement and Attack/Casting Speeds +5',
      'Critical Hit +5',
      'Back/Critical hits: +15 fixed damage',
      'Critical hits: recover 17 HP',
      'Hits: recover 12 HP',
      'All Special Attack Extra Damage +18%',
    ],
    duration: '15 min',
    cooldown: '10 sec',
    stackNote: 'Only the last draught effect applies.',
  ),
  'elixir of indignation': _buffInfo(
    title: 'Elixir of Indignation',
    kind: 'Draught',
    summary:
        'High-risk offensive draught with AP, human damage, and special attack damage.',
    effects: <String>[
      'Extra AP Against Adventurers +25',
      'Extra AP Against Humans +25',
      'All Special Attack Extra Damage +12%',
      'Movement Speed +3',
      'Critical Hit +3',
      'Max Stamina +200',
      'Max HP -150',
      'All Damage Reduction -20',
      'All Evasion -20',
    ],
    duration: '15 min',
    cooldown: '10 sec',
    stackNote:
        'Draught effects do not stack with other elixir/draught effects, except perfumes and whale tendon elixirs.',
  ),
  'elixir of frenzy': _buffInfo(
    title: 'Elixir of Frenzy',
    kind: 'Elixir',
    summary: 'Offensive party elixir that trades DP for AP.',
    effects: <String>['All AP +10', 'All DP -5'],
    duration: '10 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'elixir of fury': _buffInfo(
    title: 'Elixir of Fury',
    kind: 'Elixir',
    summary: 'Basic AP elixir used in the Fury Draught chain.',
    effects: <String>['All AP +5'],
    duration: '10 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'elixir of endless fury': _buffInfo(
    title: 'Elixir of Endless Fury',
    kind: 'Elixir',
    summary: 'Stronger AP elixir used in simple alchemy upgrades.',
    effects: <String>['All AP +8'],
    duration: '15 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'elixir of advanced concentration': _buffInfo(
    title: 'Elixir of Advanced Concentration',
    kind: 'Elixir',
    summary: 'Accuracy elixir used in the Fury Draught chain.',
    effects: <String>['All Accuracy +12'],
    duration: '15 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'defense elixir': _buffInfo(
    title: 'Defense Elixir',
    kind: 'Elixir',
    summary: 'Basic damage-reduction elixir used in the Adaptation chain.',
    effects: <String>['All Damage Reduction +5'],
    duration: '10 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'elixir of steel defense': _buffInfo(
    title: 'Elixir of Steel Defense',
    kind: 'Elixir',
    summary: 'Stronger damage-reduction elixir.',
    effects: <String>['All Damage Reduction +10'],
    duration: '15 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'elixir of wind': _buffInfo(
    title: 'Elixir of Wind',
    kind: 'Elixir',
    summary: 'Attack speed elixir used in the Potential chain.',
    effects: <String>['Attack Speed +2'],
    duration: '10 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'elixir of swiftness': _buffInfo(
    title: 'Elixir of Swiftness',
    kind: 'Elixir',
    summary: 'Movement speed elixir used in the Potential chain.',
    effects: <String>['Movement Speed +2'],
    duration: '10 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'elixir of time': _buffInfo(
    title: 'Elixir of Time',
    kind: 'Elixir',
    summary: 'Life EXP elixir for life-skill sessions.',
    effects: <String>['Life EXP +10%'],
    duration: '10 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'elixir of lethal destruction': _buffInfo(
    title: 'Elixir of Lethal Destruction',
    kind: 'Elixir',
    summary: 'Special-attack damage elixir.',
    effects: <String>['All Special Attack Extra Damage +2%'],
    duration: '15 min',
    cooldown: '1 sec',
    stackNote: 'Applies to up to 5 party members.',
  ),
  'perfume of courage': _buffInfo(
    title: 'Perfume of Courage',
    kind: 'Perfume',
    summary: 'Offensive perfume for AP, HP, and speed caps.',
    effects: <String>[
      'All AP +20',
      'Max HP +200',
      'Attack Speed +5',
      'Casting Speed +5',
      'Movement Speed +5',
    ],
    duration: '20 min',
    cooldown: '10 sec',
    stackNote: 'Only the last perfume effect applies.',
  ),
  'perfume of swiftness': _buffInfo(
    title: 'Perfume of Swiftness',
    kind: 'Perfume',
    summary:
        'Life-skill perfume for weight, Life EXP, and gathering/fishing speed.',
    effects: <String>[
      'Weight Limit +200 LT',
      'Life EXP +20%',
      'Movement Speed +5',
      'Gathering Speed +5',
      'Fishing Speed +5',
    ],
    duration: '20 min',
    cooldown: '10 sec',
    stackNote: 'Only the last perfume effect applies.',
  ),
  'perfume of deep sea': _buffInfo(
    title: 'Perfume of Deep Sea',
    kind: 'Perfume',
    summary: 'Offensive perfume for AP and special attack damage.',
    effects: <String>[
      'All AP +10',
      'Max Stamina +100',
      'Max HP +100',
      'Back Attack Extra Damage +10%',
      'Down Attack Extra Damage +10%',
      'Air Attack Extra Damage +10%',
    ],
    duration: '20 min',
    cooldown: '10 sec',
    stackNote: 'Only the last perfume effect applies.',
  ),
  'perfume of khalk': _buffInfo(
    title: 'Perfume of Khalk',
    kind: 'Perfume',
    summary: 'Defensive perfume for resistance, DR, HP, and movement.',
    effects: <String>[
      'All Resistance +10%',
      'All Damage Reduction +15',
      'Max HP +100',
      'Movement Speed +5%',
    ],
    duration: '20 min',
    cooldown: '10 sec',
    stackNote: 'Only the last perfume effect applies.',
  ),
  'perfume of charm': _buffInfo(
    title: 'Perfume of Charm',
    kind: 'Perfume',
    summary: 'Defensive perfume for evasion and a large HP boost.',
    effects: <String>['All Evasion +25', 'Max HP +750', 'Movement Speed +5%'],
    duration: '20 min',
    cooldown: '10 sec',
    stackNote: 'Only the last perfume effect applies.',
  ),
  'blessing of mystic beasts - all ap': _mysticBeastsInfo(
    title: 'Blessing of Mystic Beasts - All AP',
    effect: 'All AP +15',
  ),
  'blessing of mystic beasts - accuracy': _mysticBeastsInfo(
    title: 'Blessing of Mystic Beasts - Accuracy',
    effect: 'All Accuracy +20',
  ),
  'blessing of mystic beasts - max hp': _mysticBeastsInfo(
    title: 'Blessing of Mystic Beasts - Max HP',
    effect: 'Max HP +100',
  ),
  'blessing of mystic beasts - damage reduction': _mysticBeastsInfo(
    title: 'Blessing of Mystic Beasts - Damage Reduction',
    effect: 'All Damage Reduction +15',
  ),
  'blessing of mystic beasts - evasion': _mysticBeastsInfo(
    title: 'Blessing of Mystic Beasts - Evasion',
    effect: 'All Evasion +20',
  ),
  'adhesive for upgrade': RecipeBookItemInfo(
    title: 'Adhesive for Upgrade',
    kind: 'Ship upgrade material',
    summary: 'A material for early Epheria ship upgrades.',
    uses: <String>[
      'Epheria ship upgrades: Sailboat → Caravel and Frigate → Galleass.',
    ],
  ),
  'graphite ingot for upgrade': RecipeBookItemInfo(
    title: 'Graphite Ingot for Upgrade',
    kind: 'Ship upgrade material',
    summary: 'A metal material for early Epheria ship upgrades.',
    uses: <String>[
      'Epheria ship upgrades: Sailboat → Caravel and Frigate → Galleass.',
    ],
  ),
  'deep tide-dyed standardized timber square': RecipeBookItemInfo(
    title: 'Deep Tide-Dyed Standardized Timber Square',
    kind: 'Ship upgrade material',
    summary: 'A structural material for Epheria Carrack upgrades.',
    uses: <String>[
      'Upgrading an Epheria Caravel or Galleass to an Epheria Carrack.',
    ],
  ),
  'tide-dyed standardized timber square': RecipeBookItemInfo(
    title: 'Tide-Dyed Standardized Timber Square',
    kind: 'Ship upgrade material',
    summary: 'A structural material for Epheria ship upgrades and equipment.',
    uses: <String>[
      'Epheria Galleass upgrades and advanced ship parts, such as Mayna Cannons.',
    ],
  ),
  'moon scale plywood': RecipeBookItemInfo(
    title: 'Moon Scale Plywood',
    kind: 'Ship upgrade material',
    summary: 'A processed wood material for Epheria ships and ship equipment.',
    uses: <String>[
      'Epheria Galleass upgrades and Caravel/Galleass ship parts, such as Upgraded Plating.',
    ],
  ),
  'wave residue adhesive': RecipeBookItemInfo(
    title: 'Wave Residue Adhesive',
    kind: 'Ship equipment material',
    summary: 'An adhesive used in advanced ship equipment.',
    uses: <String>[
      'Epheria Carrack and Panokseon equipment made in their ship-part workshops.',
    ],
  ),
  'ship repair material': RecipeBookItemInfo(
    title: 'Ship Repair Material',
    kind: 'Ship repair material',
    summary: 'A consumable material for repairing large ships.',
    uses: <String>[
      "Repairs 2% of a large ship's durability and makes Emergency Ship Repair Kits.",
    ],
  ),
  'flawless magical black stone': RecipeBookItemInfo(
    title: 'Flawless Magical Black Stone',
    kind: 'Enhancement material',
    summary: 'An enhancement stone made specifically for Blackstar gear.',
    uses: <String>['Enhances Blackstar gear.'],
  ),
  'black stone powder': RecipeBookItemInfo(
    title: 'Black Stone Powder',
    kind: 'Workshop and processing material',
    summary:
        'A general-purpose material used in workshops and processing recipes.',
    uses: <String>[
      'Used in worker workshops, equipment and furniture recipes, and certain bulk-processing recipes.',
    ],
    howToObtain: <String>[
      'Grind a Black Stone or eligible Magic Crystal, craft it at a Refinery, or buy it from the Central Market.',
    ],
  ),
  'black gem fragment': RecipeBookItemInfo(
    title: 'Black Gem Fragment',
    kind: 'Life Skill crafting material',
    summary:
        'The raw precursor used to make Black Gems; it is not an enhancement stone by itself.',
    uses: <String>[
      'Combine it with Black Stones through Simple Alchemy to make Black Gems.',
    ],
  ),
  'black gem': RecipeBookItemInfo(
    title: 'Black Gem',
    kind: 'Life Skill enhancement material',
    summary:
        'A fixed-chance enhancement material for eligible Life Mastery equipment.',
    uses: <String>[
      'Enhances eligible Life Mastery clothes from +1 to +15 and Loggia Life accessories.',
    ],
    notes: <String>[
      'Normal Enhancement Chance stacks do not affect attempts made with it.',
    ],
  ),
  'concentrated magical black gem': RecipeBookItemInfo(
    title: 'Concentrated Magical Black Gem',
    kind: 'Life Skill enhancement material',
    summary:
        'A higher-grade, fixed-chance enhancement material for Life Mastery clothes and accessories.',
    uses: <String>[
      'Enhances eligible Life Mastery clothes from PRI to PEN, Geranoa and Manos accessories, and Preonne accessories through DEC (X).',
    ],
    notes: <String>[
      'Normal Enhancement Chance stacks do not affect attempts made with it.',
      'It does not enhance Life Skill tools.',
    ],
  ),
  'black stone': RecipeBookItemInfo(
    title: 'Black Stone',
    kind: 'Enhancement material',
    summary:
        'The unified basic enhancement stone for eligible ordinary gear and Life Skill tools.',
    uses: <String>[
      'Enhances eligible weapons and defense gear through +15, and eligible Life Skill tools at their lower enhancement levels.',
      'Also used to make Black Gems and Concentrated Magical Black Stones.',
    ],
  ),
  'concentrated magical black stone': RecipeBookItemInfo(
    title: 'Concentrated Magical Black Stone',
    kind: 'Enhancement material',
    summary:
        'A higher-grade enhancement stone for eligible PRI to PEN gear and Life Skill tools.',
    uses: <String>[
      'Enhances eligible weapons and defense gear from PRI to PEN.',
    ],
  ),
  'memory fragment': RecipeBookItemInfo(
    title: 'Memory Fragment',
    kind: 'Durability repair material',
    summary: 'A repair material that restores an item\'s maximum durability.',
    uses: <String>['Restores maximum durability on most gear.'],
  ),
  'black stone (armor)': RecipeBookItemInfo(
    title: 'Black Stone (Armor)',
    kind: 'Legacy enhancement material',
    summary:
        'Removed from the current item system and replaced by Black Stone.',
  ),
  'concentrated magical black stone (armor)': RecipeBookItemInfo(
    title: 'Concentrated Magical Black Stone (Armor)',
    kind: 'Legacy enhancement material',
    summary:
        'Removed from the current item system and replaced by Concentrated Magical Black Stone.',
  ),
  'hard black crystal shard': RecipeBookItemInfo(
    title: 'Hard Black Crystal Shard',
    kind: 'Legacy enhancement material',
    summary:
        'Removed from the current item system and replaced by Sharp Black Crystal Shard.',
  ),
  'flawless chaotic black stone': RecipeBookItemInfo(
    title: 'Flawless Chaotic Black Stone',
    kind: 'Enhancement material',
    summary:
        'An enhancement stone made specifically for Slumbering Origin armor.',
    uses: <String>[
      "Enhances Slumbering Origin armor, such as Fallen God's Armor.",
    ],
  ),
  'ultimate weapon reform stone': RecipeBookItemInfo(
    title: 'Ultimate Weapon Reform Stone',
    kind: 'Gear reform material',
    summary: 'A reform stone that upgrades eligible weapons to Ultimate.',
    uses: <String>[
      'Reforms eligible weapons to Ultimate through the Black Spirit.',
    ],
    howToObtain: <String>[
      "Refinery Lv. 3: 50 Steel + 1 Sharp Black Crystal Shard + 30 Black Crystal + 20 Red Tree Lump + 20 Clown's Blood + 400 Black Stone Powder.",
      "Exchange 100 Hunter's Seals with Thyshelle Arms in Tarif.",
    ],
  ),
  'ultimate armor reform stone': RecipeBookItemInfo(
    title: 'Ultimate Armor Reform Stone',
    kind: 'Gear reform material',
    summary: 'A reform stone that upgrades eligible armor to Ultimate.',
    uses: <String>[
      'Reforms eligible armor to Ultimate through the Black Spirit.',
    ],
    howToObtain: <String>[
      "Refinery Lv. 3: 40 Steel + 1 Sharp Black Crystal Shard + 30 Black Crystal + 20 Old Tree Bark + 20 Clown's Blood + 400 Black Stone Powder.",
      "Exchange 50 Hunter's Seals with Thyshelle Arms in Tarif.",
    ],
  ),
  'blessed soul fragment': RecipeBookItemInfo(
    title: 'Blessed Soul Fragment',
    kind: 'Alchemy stone reform material',
    summary: 'A reform material for yellow-grade or better alchemy stones.',
    uses: <String>[
      'Reforms a yellow-grade or better alchemy stone to Blessed.',
    ],
    example: "Vell's Heart → Blessed Vell's Heart.",
  ),
  'refined essence of emotions': RecipeBookItemInfo(
    title: 'Refined Essence of Emotions',
    kind: 'Accessory reform material',
    summary: 'An extraction material for reformed accessories.',
    uses: <String>['Removes and recovers a cup from a reformed accessory.'],
  ),
  "krogdalo's origin stone": RecipeBookItemInfo(
    title: "Krogdalo's Origin Stone",
    kind: 'Dream Horse material',
    summary: 'A Courser Awakening material used for Dream Horse attempts.',
    uses: <String>[
      'Courser Awakening attempts for a Dream Horse, such as Arduanatt.',
    ],
  ),
  'sunset glow crystal': RecipeBookItemInfo(
    title: 'Sunset Glow Crystal',
    kind: 'Shai gear reform material',
    summary: 'A reform material made specifically for Shai\'s Artina Sol.',
    uses: <String>[
      "Reforms Shai's Artina Sol into Sunset Artina Sol, adding Extra AP Against Monsters +35.",
    ],
  ),
  'solar black stone': RecipeBookItemInfo(
    title: 'Solar Black Stone',
    kind: 'Legacy enhancement material',
    summary:
        'A retired ship-enhancement item that can be exchanged for Tidal Black Stones.',
    uses: <String>[
      'Exchange remaining copies with the Black Spirit for 20 Tidal Black Stones.',
    ],
    howToObtain: <String>[
      'Legacy item: its former processing recipe was discontinued.',
    ],
  ),
  'lunar black stone': RecipeBookItemInfo(
    title: 'Lunar Black Stone',
    kind: 'Legacy enhancement material',
    summary:
        'A retired ship-enhancement item that can be exchanged for Tidal Black Stones.',
    uses: <String>[
      'Exchange remaining copies with the Black Spirit for 30 Tidal Black Stones.',
    ],
    howToObtain: <String>[
      'Legacy item: its former processing recipe was discontinued.',
    ],
  ),
  'frosted black stone': RecipeBookItemInfo(
    title: 'Frosted Black Stone',
    kind: 'Legacy ship enhancement material',
    summary: 'A retired ship-enhancement item replaced by Tidal Black Stone.',
    uses: <String>[
      'Exchange remaining copies with the Black Spirit for 2 Tidal Black Stones.',
    ],
    howToObtain: <String>[
      'Legacy item: it is no longer obtainable through its former routes.',
    ],
  ),
  'tidal black stone': RecipeBookItemInfo(
    title: 'Tidal Black Stone',
    kind: 'Ship equipment enhancement material',
    summary:
        'The current enhancement stone for Epheria, Carrack, and Panokseon ship equipment.',
    uses: <String>['Enhances eligible ship equipment with guaranteed success.'],
  ),
  'essence of dawn': RecipeBookItemInfo(
    title: 'Essence of Dawn',
    kind: 'Kharazad enhancement material',
    summary:
        'A material for crafting and enhancing Kharazad accessories and for JIN Dawn Crystal - All AP.',
    uses: <String>[
      'Crafts Kharazad accessories with matching Deboreka accessories and Magical Shards.',
      'Enhances Kharazad accessories from +0 through NOV (IX).',
      'Crafts JIN Dawn Crystal - All AP.',
    ],
    howToObtain: <String>[
      'Earn it from eligible Black Shrine - Donghae Boss Blitz rewards, or buy it from the Central Market.',
      "Heat eligible enhanced accessories with Dawn's Aura from an Old Moon Manager.",
    ],
  ),
  'caphras stone': RecipeBookItemInfo(
    title: 'Caphras Stone',
    kind: 'Enhancement material',
    summary: 'Enhancement material used in several late-game recipes.',
    uses: <String>[
      'Inserted into eligible PEN boss gear for Caphras levels and Slumbering Origin progression.',
    ],
    craftUses: <RecipeBookCraftUse>[
      RecipeBookCraftUse(output: 'Primordial Black Stone'),
    ],
  ),
  'ancient spirit dust': RecipeBookItemInfo(
    title: 'Ancient Spirit Dust',
    kind: 'Enhancement material',
    summary: 'Material used to make Caphras Stones.',
    craftUses: <RecipeBookCraftUse>[
      RecipeBookCraftUse(output: 'Caphras Stone'),
    ],
  ),
  'exalted soul fragment': RecipeBookItemInfo(
    title: 'Exalted Soul Fragment',
    kind: 'Alchemy stone reform material',
    summary:
        'Upgrades a Blessed alchemy stone to Exalted and adds All Damage Reduction +2.',
    example: "Blessed Vell's Heart.",
  ),
  'magical shard': RecipeBookItemInfo(
    title: 'Magical Shard',
    kind: 'Gear and crystal material',
    summary:
        'Material used in crystals, reform stones, and late-game gear recipes.',
    uses: <String>[
      'Used in Crimson/Violet Primordial Pigment and Primordial Glow Crystal.',
    ],
    howToObtain: <String>[
      'Buy from the Central Market.',
      'Heat a Sealed Black Magic Crystal or another yellow-grade Black Magic Crystal.',
      'Bulk: heat 10 Sealed Black Magic Crystals with 1 Black Stone Powder.',
    ],
  ),
  'magical lightstone crystal': RecipeBookItemInfo(
    title: 'Magical Lightstone Crystal',
    kind: 'Lightstone material',
    summary:
        'Material used for purified and amplified lightstones and high-grade crystals.',
    uses: <String>[
      'Used in Purified and Amplified Lightstones.',
      'Used in many high-grade crystal and Blessing of Mystic Beasts recipes.',
    ],
    howToObtain: <String>[
      'Exchange unwanted or Imperfect Lightstones with Dalishain in major towns; the amount received depends on the lightstone.',
    ],
  ),
  'sharp black crystal shard': RecipeBookItemInfo(
    title: 'Sharp Black Crystal Shard',
    kind: 'Enhancement material',
    summary:
        'A crafting shard used to make advanced enhancement stones and gear materials.',
    uses: <String>[
      'Makes Concentrated Magical Black Stone, Concentrated Magical Black Gem, and several late-game materials.',
    ],
  ),
  'primordial black stone': RecipeBookItemInfo(
    title: 'Primordial Black Stone',
    kind: 'Sovereign enhancement material',
    summary: 'An enhancement stone made specifically for Sovereign weapons.',
    uses: <String>['Enhances Sovereign weapons.'],
  ),
  'flame of the primordial': RecipeBookItemInfo(
    title: 'Flame of the Primordial',
    kind: 'Sovereign material',
    summary:
        'Primordial/Sovereign-chain material used by higher tier primordial recipes.',
  ),
  'gem of the primordial': RecipeBookItemInfo(
    title: 'Gem of the Primordial',
    kind: 'Sovereign material',
    summary:
        'Primordial/Sovereign-chain material used around weapon color and gear progression recipes.',
  ),
};

RecipeBookItemInfo _buffInfo({
  required String title,
  required String kind,
  required String summary,
  required List<String> effects,
  required String duration,
  required String cooldown,
  String? stackNote,
}) {
  return RecipeBookItemInfo(
    title: title,
    kind: kind,
    summary: summary,
    effects: effects,
    notes: <String>['Duration: $duration.', 'Cooldown: $cooldown.', ?stackNote],
  );
}

RecipeBookItemInfo _mysticBeastsInfo({
  required String title,
  required String effect,
}) {
  return _buffInfo(
    title: title,
    kind: 'Blessing',
    summary:
        'Portable version of the Hunting furniture buff. Useful when comparing house-buff options.',
    effects: <String>[effect],
    duration: '60 min',
    cooldown: '10 sec',
    stackNote:
        'Does not stack with regular residence furniture buffs; only the most recent scroll or furniture buff applies.',
  );
}

RecipeBookItemInfo _exactBuffHoverInfo(
  ExactBuffInfo info,
  String foldedName, {
  required Recipe? recipe,
  required List<Recipe> consumers,
}) {
  return RecipeBookItemInfo(
    title: info.title,
    kind: _buffKind(foldedName, ''),
    summary: '',
    effects: info.effects,
    craftUses: _compactCraftUses(consumers, limit: 1),
    acquisitionFormulas: _recipeBookFormulas(recipe),
    acquisitionNotes: _compactAcquisitionNotes(recipe),
    notes: <String>[
      if (info.duration.isNotEmpty) 'Duration: ${info.duration}.',
      if (info.cooldown.isNotEmpty) 'Cooldown: ${info.cooldown}.',
      if (info.party) 'Applies to up to 5 party members.',
      if (foldedName.startsWith('immortal: '))
        'Immortal version: effects persist if you die.',
      if (_buffKind(foldedName, '') == 'Draught')
        'Only the last draught effect applies.',
      if (_buffKind(foldedName, '') == 'Perfume')
        'Only the last perfume effect applies.',
      if (foldedName.startsWith('blessing of mystic beasts'))
        'Does not stack with other residence furniture buffs.',
    ],
  );
}

RecipeBookItemInfo _exactFoodHoverInfo(
  ExactFoodInfo info, {
  required Recipe? recipe,
  required List<Recipe> consumers,
}) {
  return RecipeBookItemInfo(
    title: info.title,
    kind: info.kind,
    summary: info.description,
    effects: info.effects,
    craftUses: _compactCraftUses(consumers, limit: 1),
    acquisitionFormulas: _recipeBookFormulas(recipe),
    acquisitionNotes: _compactAcquisitionNotes(recipe),
    notes: <String>[
      if (info.duration.isNotEmpty) 'Duration: ${info.duration}.',
      if (info.cooldown.isNotEmpty) 'Cooldown: ${info.cooldown}.',
    ],
  );
}

RecipeBookItemInfo _variantInfo({
  required String title,
  required RecipeBookItemInfo baseInfo,
  required String note,
}) {
  return RecipeBookItemInfo(
    title: title,
    kind: baseInfo.kind,
    summary: baseInfo.summary,
    effectsTitle: baseInfo.effectsTitle,
    effects: baseInfo.effects,
    uses: baseInfo.uses,
    craftUses: baseInfo.craftUses,
    acquisitionFormulas: baseInfo.acquisitionFormulas,
    acquisitionNotes: baseInfo.acquisitionNotes,
    example: baseInfo.example,
    notes: <String>[...baseInfo.notes, note],
  );
}

RecipeBookItemInfo _completeCuratedInfo(
  RecipeBookItemInfo curated, {
  required Recipe? recipe,
  required List<Recipe> consumers,
}) {
  return RecipeBookItemInfo(
    title: curated.title,
    kind: curated.kind,
    summary: curated.summary,
    effectsTitle: curated.effectsTitle,
    effects: curated.effects,
    uses: curated.uses,
    craftUses: _mergeCraftUses(curated.craftUses, consumers),
    acquisitionFormulas: curated.acquisitionFormulas.isNotEmpty
        ? curated.acquisitionFormulas
        : _recipeBookFormulas(recipe),
    acquisitionNotes: curated.acquisitionNotes.isNotEmpty
        ? curated.acquisitionNotes
        : _compactAcquisitionNotes(recipe),
    example: curated.example,
    notes: curated.notes,
  );
}

List<RecipeBookCraftUse> _mergeCraftUses(
  List<RecipeBookCraftUse> curated,
  Iterable<Recipe> consumers,
) {
  final result = <RecipeBookCraftUse>[...curated];
  for (final use in _compactCraftUses(consumers, limit: 2)) {
    final existingIndex = result.indexWhere(
      (existing) => _sameName(existing.output, use.output),
    );
    if (existingIndex >= 0) {
      if (result[existingIndex].formulas.isEmpty && use.formulas.isNotEmpty) {
        result[existingIndex] = result[existingIndex].copyWith(
          formulas: use.formulas,
        );
      }
      continue;
    }
    result.add(use);
    break;
  }
  return List<RecipeBookCraftUse>.unmodifiable(result);
}

RecipeBookItemInfo _finishItemInfo(
  RecipeBookItemInfo info, {
  required String name,
  required Recipe? recipe,
  required List<Recipe> consumers,
}) {
  final purpose = recipeBookItemPurposeFor(
    name: name,
    recipe: recipe,
    currentKind: info.kind,
    hasCraftUses: info.craftUses.isNotEmpty,
  );
  final purposeDescription = purpose.description.trim();
  final existingDescription = info.summary.trim();
  final description =
      existingDescription.isEmpty || _isWeakItemCopy(existingDescription)
      ? purposeDescription
      : existingDescription;
  final effects = _uniqueLines(<String>[...info.effects, ...purpose.effects]);
  final uses = _uniqueLines(<String>[...info.uses, ...purpose.uses])
      .where(
        (line) => !_informationCoveredByReferences(line, <String>[
          description,
          ...effects,
        ]),
      )
      .toList(growable: false);
  final acquisitionFormulas = info.acquisitionFormulas.isNotEmpty
      ? info.acquisitionFormulas
      : _recipeBookFormulas(recipe);
  final acquisitionNotes = _uniqueLines(info.acquisitionNotes)
      .where(
        (note) => !acquisitionFormulas.any(
          (formula) =>
              _sameInformation(note, recipeBookFormulaSummary(formula)),
        ),
      )
      .toList(growable: false);
  final howToObtain = <String>[
    ...acquisitionFormulas.map(recipeBookFormulaSummary),
    ...acquisitionNotes,
  ];
  final notes = _uniqueLines(<String>[...info.notes, ...purpose.notes])
      .where((line) => !_sameInformation(line, description))
      .where((line) => !uses.any((use) => _sameInformation(line, use)))
      .where(
        (line) => !howToObtain.any((route) => _sameInformation(line, route)),
      )
      .toList(growable: false);
  final purposeKind = purpose.kind?.trim() ?? '';
  final kind = purposeKind.isEmpty ? info.kind.trim() : purposeKind;
  final example = info.example?.trim().isNotEmpty ?? false
      ? info.example!.trim()
      : purpose.example?.trim();

  return RecipeBookItemInfo(
    title: info.title.trim().isEmpty ? name : info.title,
    kind: kind.isEmpty ? 'Item' : kind,
    summary: description,
    effectsTitle: info.effectsTitle,
    effects: List<String>.unmodifiable(effects),
    uses: List<String>.unmodifiable(uses),
    craftUses: info.craftUses,
    acquisitionFormulas: List<RecipeBookFormula>.unmodifiable(
      acquisitionFormulas,
    ),
    acquisitionNotes: List<String>.unmodifiable(acquisitionNotes),
    example: example?.isEmpty ?? true ? null : example,
    notes: List<String>.unmodifiable(notes),
  );
}

RecipeBookItemInfo _compactItemInfo({
  required String name,
  required Recipe? recipe,
  required List<Recipe> consumers,
}) {
  final craftUses = _compactCraftUses(consumers, limit: 1);
  return RecipeBookItemInfo(
    title: name,
    kind: _compactKind(name, recipe),
    summary: '',
    craftUses: craftUses,
    acquisitionFormulas: _recipeBookFormulas(recipe),
    acquisitionNotes: _compactAcquisitionNotes(recipe),
  );
}

List<String> _uniqueLines(Iterable<String> values) {
  final result = <String>[];
  final identities = <String>{};
  for (final value in values) {
    final line = value.trim();
    if (line.isEmpty) continue;
    final identity = _informationIdentity(line);
    if (identity.isEmpty || !identities.add(identity)) continue;
    result.add(line);
  }
  return result;
}

bool _sameLines(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameInformation(String left, String right) {
  if (left.trim().isEmpty || right.trim().isEmpty) return false;
  if (_informationIdentity(left) == _informationIdentity(right)) return true;
  final leftTerms = _informationTerms(left);
  final rightTerms = _informationTerms(right);
  return leftTerms.length >= 3 &&
      leftTerms.length == rightTerms.length &&
      leftTerms.containsAll(rightTerms);
}

List<String> _uniqueInformationSentences(
  Iterable<String> values, {
  required Iterable<String> coveredBy,
}) {
  final references = coveredBy
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: true);
  final result = <String>[];
  for (final value in values) {
    for (final sentence in _splitInformationSentences(value)) {
      if (_informationCoveredByReferences(sentence, references)) continue;
      if (_informationCoveredByReferences(sentence, result)) continue;
      result.add(sentence);
    }
  }
  return result;
}

List<String> _splitInformationSentences(String value) {
  final text = value.trim();
  if (text.isEmpty) return const <String>[];
  final result = <String>[];
  var start = 0;
  for (var index = 0; index < text.length; index++) {
    final character = text[index];
    if (character != '.' && character != '!' && character != '?') continue;
    final isBoundary =
        index + 1 == text.length || RegExp(r'\s').hasMatch(text[index + 1]);
    if (!isBoundary) continue;
    final sentence = text.substring(start, index + 1).trim();
    if (sentence.isNotEmpty) result.add(sentence);
    start = index + 1;
  }
  final remainder = text.substring(start).trim();
  if (remainder.isNotEmpty) result.add(remainder);
  return result;
}

bool _informationCoveredByReferences(
  String candidate,
  Iterable<String> references,
) {
  final referenceList = references
      .where((reference) => reference.trim().isNotEmpty)
      .toList(growable: false);
  if (referenceList.any(
    (reference) => _sameInformation(candidate, reference),
  )) {
    return true;
  }
  final candidateTerms = _informationTerms(candidate);
  if (candidateTerms.length < 3) return false;
  final referenceTerms = <String>{
    for (final reference in referenceList) ..._informationTerms(reference),
  };
  return referenceTerms.containsAll(candidateTerms);
}

String _informationIdentity(String value) {
  return _fold(value)
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'\b(the|a|an|item|used|use|uses|for|to)\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

Set<String> _informationTerms(String value) {
  const ignored = <String>{
    'a',
    'an',
    'and',
    'another',
    'for',
    'from',
    'gain',
    'in',
    'into',
    'is',
    'it',
    'its',
    'listed',
    'named',
    'of',
    'on',
    'one',
    'same',
    'the',
    'this',
    'through',
    'to',
    'use',
    'used',
    'uses',
    'with',
  };
  return _fold(value)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.isNotEmpty && !ignored.contains(term))
      .map(_informationTermStem)
      .toSet();
}

String _informationTermStem(String term) {
  if (term.startsWith('enhanc')) return 'enhance';
  if (term.startsWith('equip')) return 'equip';
  if (term.startsWith('craft')) return 'craft';
  if (term.startsWith('infus')) return 'infuse';
  if (term.startsWith('appl')) return 'apply';
  if (term.startsWith('consum')) return 'consume';
  if (term.length > 4 && term.endsWith('s')) {
    return term.substring(0, term.length - 1);
  }
  return term;
}

bool _isWeakItemCopy(String value) {
  final folded = _fold(value);
  return <String>[
    'basic recipe material',
    'crafting material',
    'gear progression material',
    'gear crystal or crystal material',
    'relevant to ',
    'related to:',
    'primordial/sovereign-chain material',
  ].any(folded.contains);
}

List<Recipe> _distinctConsumers(
  Iterable<Recipe> consumerRecipes,
  String itemName,
) {
  final seen = <String>{};
  return consumerRecipes
      .where((consumer) => !_sameName(consumer.name, itemName))
      .where((consumer) => seen.add(_fold(consumer.name)))
      .toList(growable: false);
}

List<RecipeBookCraftUse> _compactCraftUses(
  Iterable<Recipe> consumers, {
  required int limit,
}) {
  return consumers
      .where((consumer) => consumer.isCraftable)
      .take(limit)
      .map(
        (consumer) => RecipeBookCraftUse(
          output: consumer.name,
          formulas: _recipeBookFormulas(consumer),
        ),
      )
      .toList(growable: false);
}

List<String> _compactAcquisitionNotes(Recipe? recipe) {
  if (recipe == null) return const <String>[];
  final vendor = recipe.vendor?.trim() ?? '';
  final location = recipe.location?.trim() ?? '';
  if (vendor.isNotEmpty) {
    return <String>[
      'Buy from $vendor${location.isEmpty ? '' : ' in $location'}.',
    ];
  }
  final sourceNote = sanitizeDisplayableSourceNote(recipe.sourceNote);
  if (sourceNote != null) return <String>[sourceNote];
  return const <String>[];
}

List<RecipeBookFormula> _recipeBookFormulas(Recipe? recipe) {
  if (recipe == null ||
      !recipe.hasRecordedRecipe ||
      (!recipe.isCraftable && !isBrowsableRecipeBookReference(recipe))) {
    return const <RecipeBookFormula>[];
  }
  if (recipe.variants.isEmpty) {
    return <RecipeBookFormula>[
      RecipeBookFormula(
        outputName: recipe.name,
        type: recipe.type,
        method: _compactMethodValues(recipe.method, recipe.type),
        baseOutput: recipe.baseOutput,
        outputMinimum: recipe.outputMinimum,
        outputMaximum: recipe.outputMaximum,
        ingredients: recipe.ingredients,
      ),
    ];
  }

  final formulas = <RecipeBookFormula>[];
  final identities = <String>{};
  for (final variant in recipe.variants) {
    final formula = RecipeBookFormula(
      outputName: recipe.name,
      type: variant.type,
      method: _compactMethodValues(variant.method, variant.type),
      variantId: variant.id,
      routeId: variant.routeId,
      routeLabel: variant.label,
      batchMultiplier: variant.batchMultiplier,
      baseOutput: variant.baseOutput,
      outputMinimum: variant.outputMinimum,
      outputMaximum: variant.outputMaximum,
      ingredients: variant.ingredients,
    );
    if (identities.add(_formulaIdentity(formula))) formulas.add(formula);
  }
  return List<RecipeBookFormula>.unmodifiable(formulas);
}

String recipeBookFormulaSummary(RecipeBookFormula formula) {
  final ingredients = formula.ingredients.map(_compactIngredient).join(' + ');
  return '${formula.method}: $ingredients.';
}

String _formulaIdentity(RecipeBookFormula formula) => <String>[
  _fold(formula.routeId ?? ''),
  formula.batchMultiplier.toString(),
  _fold(formula.method),
  _fold(formula.type),
  formula.outputEstimated.toString(),
  for (final ingredient in formula.ingredients) ...<String>[
    _fold(ingredient.name),
    _compactQuantity(ingredient.quantity),
    for (final option in ingredient.options) _fold(option),
    for (final ratio in ingredient.substituteRatios.entries) ...<String>[
      _fold(ratio.key),
      _compactQuantity(ratio.value),
    ],
  ],
].join('|');

String _compactMethodValues(String? methodValue, String typeValue) {
  final method = methodValue?.trim() ?? '';
  if (method.isNotEmpty && _fold(method) != 'base item') return method;
  return switch (_fold(typeValue)) {
    'alchemy' => 'Alchemy',
    'cooking' => 'Cooking',
    'simple_alchemy' => 'Simple Alchemy',
    'processing' => 'Processing',
    'gathered' => 'Gathering',
    _ => 'Recipe',
  };
}

String _compactIngredient(Ingredient ingredient) {
  final alternatives = <String>{
    ...ingredient.options,
    ...ingredient.substituteRatios.keys,
  }.where((candidate) => !_sameName(candidate, ingredient.name));
  return '${_compactQuantity(ingredient.quantity)} ${ingredient.name}'
      '${alternatives.isEmpty ? '' : ' (or substitute)'}';
}

String _compactQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _compactKind(String name, Recipe? recipe) {
  final foldedName = _fold(name);
  final group = _fold(recipe?.group ?? '');
  final method = recipe?.method?.trim() ?? '';
  final type = _fold(recipe?.type ?? '');

  if (foldedName.endsWith(' plank') ||
      foldedName.endsWith(' plywood') ||
      foldedName.endsWith(' timber')) {
    return 'Wood material';
  }
  if (_looksLikeBossReformCrystal(foldedName)) {
    return 'Boss reform material';
  }
  if (_looksLikePureMetalCrystal(foldedName)) {
    return 'Processing material';
  }
  if (_looksLikeSocketableLightstone(foldedName)) return 'Lightstone';
  if (foldedName.contains('lightstone')) return 'Lightstone material';
  if (_looksLikeSocketableCrystal(foldedName)) return 'Gear crystal';
  if (foldedName.contains('crystal')) return 'Crystal material';
  if (foldedName.contains('draught')) return 'Draught';
  if (foldedName.contains('perfume')) return 'Perfume';
  if (foldedName.contains('elixir')) return 'Elixir';
  if (group.contains('enhancement')) return 'Enhancement material';
  if (group.contains('reagent')) return 'Alchemy reagent';
  if (group == 'oils') return 'Alchemy oil';
  if (group.contains('blood') && foldedName.endsWith(' blood')) {
    return type == 'alchemy' ? 'Alchemy blood' : 'Blood material';
  }
  if (group.contains('mushroom')) return 'Mushroom';
  if (group.contains('cooking material')) return 'Cooking material';
  if (group == 'cooking') {
    return type == 'cooking' ? 'Cooking material' : 'Cooking item';
  }
  if (group == 'meals') return 'Dish';
  if (type == 'cooking') return 'Cooking material';
  if (group.contains('alchemy material')) return 'Alchemy material';
  if (group.startsWith('processing - ') &&
      method.isNotEmpty &&
      _fold(method) != 'base item') {
    return '$method material';
  }
  return switch (type) {
    'alchemy' || 'simple_alchemy' => 'Alchemy item',
    'processing' => 'Processing material',
    'gathered' => 'Recipe material',
    _ => 'Recipe material',
  };
}

String _buffKind(String foldedName, String foldedGroup) {
  if (foldedName.contains('blessing of mystic beasts')) return 'Blessing';
  if (foldedName.contains('perfume') || foldedGroup.contains('perfume')) {
    return 'Perfume';
  }
  if (foldedName.contains('draught') || foldedGroup.contains('draught')) {
    return 'Draught';
  }
  return 'Elixir';
}

RecipeBookItemInfo _exactCrystalHoverInfo(
  ExactCrystalInfo info, {
  required String foldedName,
  required List<Recipe> consumers,
  required Recipe? recipe,
}) {
  return RecipeBookItemInfo(
    title: info.title,
    kind: info.kind?.trim().isNotEmpty ?? false
        ? info.kind!.trim()
        : _crystalKind(foldedName, info),
    summary: '',
    effectsTitle: info.effectsTitle,
    effects: info.effects,
    uses: _compactExactUses(info.uses),
    craftUses: _compactCraftUses(consumers, limit: 1),
    acquisitionFormulas: _recipeBookFormulas(recipe),
    acquisitionNotes: _compactAcquisitionNotes(recipe),
  );
}

List<String> _compactExactUses(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final compact = _compactExactUse(value);
    if (compact.isEmpty || !seen.add(_fold(compact))) continue;
    result.add(compact);
    if (result.length == 3) break;
  }
  return List<String>.unmodifiable(result);
}

String _compactExactUse(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('Hand over unwanted Lightstone x3')) {
    return 'Exchange 3 unwanted Lightstones with Dalishain for 1 Purified Lightstone.';
  }
  if (trimmed.startsWith('Hand over Lightstone')) {
    return 'Exchange it with Dalishain for Magical Lightstone Crystals.';
  }
  if (trimmed.startsWith('Enhancement level protection for ')) {
    final level = trimmed.contains('Distorted') ? 'Distorted' : 'Silent';
    return 'Protects $level Slumbering Origin gear from an enhancement-level drop. Consumed either way; failure adds no Enhancement Chance.';
  }

  var compact = trimmed;
  if (compact.startsWith('Obtain ')) {
    compact = compact.substring('Obtain '.length);
    final processIndex = compact.indexOf('Processing');
    if (processIndex >= 0) compact = compact.substring(0, processIndex);
    compact = compact.replaceFirst(RegExp(r'by\s*$'), '');
    return _sentence(compact);
  }
  if (compact.startsWith('Craft the following items')) {
    compact = compact.substring('Craft the following items'.length);
    compact = compact.replaceAllMapped(
      RegExp(r'x(\d+)(?=[A-Z])'),
      (match) => 'x${match.group(1)} + ',
    );
    return 'Process into ${_sentence(compact)}';
  }
  if (compact.startsWith('Craft ')) {
    compact = compact.substring('Craft '.length);
    for (final marker in <String>[
      '- Crafting Method',
      '- Crafting Materials',
      '(Enhance ',
    ]) {
      final markerIndex = compact.indexOf(marker);
      if (markerIndex >= 0) compact = compact.substring(0, markerIndex);
    }
    final object = _sentence(compact);
    return object.isEmpty ? '' : 'Used to craft $object';
  }
  return _sentence(compact);
}

String _sentence(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return '';
  return trimmed.endsWith('.') ? trimmed : '$trimmed.';
}

String _crystalKind(String foldedName, ExactCrystalInfo info) {
  if (_looksLikeBossReformCrystal(foldedName)) {
    return 'Boss reform material';
  }
  if (_looksLikeSocketableLightstone(foldedName) && info.effects.isNotEmpty) {
    return 'Lightstone';
  }
  if (foldedName.contains('lightstone')) return 'Lightstone material';
  if (info.effects.isNotEmpty || _looksLikeSocketableCrystal(foldedName)) {
    return 'Gear crystal';
  }
  if (_looksLikePureMetalCrystal(foldedName)) {
    return 'Processing material';
  }
  if (foldedName.contains('shard')) {
    return 'Crystal material';
  }
  return 'Crystal material';
}

bool _looksLikeSocketableLightstone(String foldedName) =>
    foldedName.startsWith('lightstone of ') ||
    foldedName.startsWith('amplified lightstone of ');

bool _looksLikeSocketableCrystal(String foldedName) =>
    foldedName.startsWith('ancient magic crystal') ||
    foldedName.startsWith('black magic crystal - ') ||
    foldedName.startsWith('bon magic crystal - ') ||
    foldedName.startsWith('combined magic crystal - ') ||
    foldedName.startsWith('jin magic crystal - ') ||
    foldedName.startsWith('magic crystal of infinity - ');

bool _looksLikeBossReformCrystal(String foldedName) =>
    foldedName == 'concentrated boss crystal' ||
    RegExp(
      r'^concentrated (bheg|dim tree spirit|giath|griffon|karanda|kutum|leebur|muskan|nouver|offin tett|red nose|urugon) crystal$',
    ).hasMatch(foldedName);

bool _looksLikePureMetalCrystal(String foldedName) => RegExp(
  r'^pure (copper|gold|iron|lead|mythril|nickel|noc|platinum|silver|tin|titanium|vanadium|zinc) crystal$',
).hasMatch(foldedName);

bool _sameName(String left, String right) => _fold(left) == _fold(right);

String _fold(String value) => value.trim().toLowerCase();
