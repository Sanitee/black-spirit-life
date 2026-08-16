import '../../domain/models/catalog_models.dart';

/// Small, player-facing facts that are not represented by the planner's
/// recipe graph. Recipe formulas and reverse recipe links remain derived from
/// the catalog; this layer explains what an item actually does in the game.
final class RecipeBookItemPurpose {
  const RecipeBookItemPurpose({
    this.kind,
    required this.description,
    this.effects = const <String>[],
    this.uses = const <String>[],
    this.notes = const <String>[],
    this.example,
  });

  final String? kind;
  final String description;
  final List<String> effects;
  final List<String> uses;
  final List<String> notes;
  final String? example;
}

RecipeBookItemPurpose recipeBookItemPurposeFor({
  required String name,
  required Recipe? recipe,
  required String currentKind,
  required bool hasCraftUses,
}) {
  final foldedName = _fold(name);
  final foldedCurrentKind = _fold(currentKind);
  final exact =
      _verifiedEffectPurposes[foldedName] ??
      _exactPurposes[foldedName] ??
      _exactEquipmentPurposes[foldedName];
  if (exact != null) return exact;

  final edaniaPartIi = _edaniaPartIiPurpose(name, foldedName);
  if (edaniaPartIi != null) return edaniaPartIi;

  final qualityFarmMaterial = _qualityFarmMaterialPurpose(foldedName);
  if (qualityFarmMaterial != null) return qualityFarmMaterial;

  final plantableSeed = _plantableSeedPurpose(name, foldedName);
  if (plantableSeed != null) return plantableSeed;

  final reformStone = _jetinaReformStonePurpose(name, foldedName);
  if (reformStone != null) return reformStone;

  final heart = _combinedAlchemyStonePurpose(name, foldedName);
  if (heart != null) return heart;

  if (foldedName.contains('primordial pigment')) {
    return const RecipeBookItemPurpose(
      kind: 'Weapon appearance material',
      description:
          'A cosmetic pigment for a Sovereign weapon or Primordial Artina Sol.',
      uses: <String>[
        "Changes the weapon's Primordial appearance; it does not enhance combat stats.",
      ],
      notes: <String>[
        'Applying another pigment replaces the current one, and the pigment cannot be extracted.',
      ],
    );
  }

  if (foldedName.contains('artifact')) {
    final itemEffect = _artifactItemEffects[foldedName];
    return RecipeBookItemPurpose(
      kind: 'Artifact',
      description: 'An equipable Artifact with two Lightstone slots.',
      effects: itemEffect == null ? const <String>[] : <String>[itemEffect],
      uses: const <String>[
        'Equip it in an Artifact slot and infuse Lightstones for additional effects.',
      ],
    );
  }

  if (_looksLikeAccessory(foldedName) &&
      !_isKnownNonGearKind(foldedCurrentKind)) {
    return const RecipeBookItemPurpose(
      kind: 'Accessory',
      description: 'An equipable accessory.',
      uses: <String>[
        'Equip it in a compatible accessory slot to gain its item stats.',
      ],
    );
  }

  if (_looksLikeArmor(foldedName) && !_isKnownNonGearKind(foldedCurrentKind)) {
    return const RecipeBookItemPurpose(
      kind: 'Defense gear',
      description: 'A piece of equipable defense gear.',
      uses: <String>[
        'Equip it in the matching armor slot to gain its item stats.',
      ],
    );
  }

  if (_looksLikeWeapon(foldedName) && !_isKnownNonGearKind(foldedCurrentKind)) {
    return const RecipeBookItemPurpose(
      kind: 'Weapon',
      description: 'Equipable class weapon.',
      uses: <String>['Equip it on a compatible class to gain its item stats.'],
    );
  }

  if (foldedName.endsWith(' feed')) {
    return const RecipeBookItemPurpose(
      kind: 'Pet feed',
      description: 'Food that restores a pet\'s hunger.',
      uses: <String>['Feed it to a pet to restore hunger.'],
    );
  }

  if (foldedName.contains('carrot juice') || foldedName == 'carrot confit') {
    return const RecipeBookItemPurpose(
      kind: 'Mount recovery item',
      description: 'Consumable recovery food for mounts.',
      uses: <String>['Use it to restore a mount\'s health.'],
    );
  }

  if (foldedName.contains('whale tendon potion')) {
    return const RecipeBookItemPurpose(
      kind: 'Recovery item',
      description: 'Emergency combat potion made from whale materials.',
      uses: <String>['Use it for an immediate recovery effect in combat.'],
    );
  }

  final kind = currentKind.trim();

  final description = _derivedDescription(
    foldedName: foldedName,
    kind: kind,
    foldedMethod: _fold(recipe?.method ?? ''),
  );
  final uses = hasCraftUses || description.isNotEmpty
      ? const <String>[]
      : _derivedTerminalUses(kind: kind);

  return RecipeBookItemPurpose(description: description, uses: uses);
}

RecipeBookItemPurpose? _edaniaPartIiPurpose(String name, String foldedName) {
  final reformedAccessory = _edaniaReformedAccessoryPurpose(foldedName);
  if (reformedAccessory != null) return reformedAccessory;

  if (RegExp(r'^ekleta (necklace|earring|ring|belt)$').hasMatch(foldedName)) {
    final slot = name.split(' ').last;
    return RecipeBookItemPurpose(
      kind: 'Ekleta accessory',
      description:
          'An Edania accessory obtained through the Kharazad exchange with Clorince.',
      uses: <String>['Equip it in the $slot slot.'],
      notes: <String>[
        'Each enhancement attempt consumes 1 Causality Shardstone - $slot.',
        'A failed enhancement reduces Max Durability by 20.',
        'At PRI or higher, a Causality Hammer prevents the enhancement level from dropping on failure.',
      ],
    );
  }
  if (foldedName.startsWith('causality shardstone - ')) {
    final slot = name.split(' - ').last;
    return RecipeBookItemPurpose(
      kind: 'Accessory enhancement material',
      description: 'A slot-specific material for enhancing an Ekleta $slot.',
      notes: const <String>[
        'A failed enhancement reduces Max Durability by 20.',
      ],
    );
  }
  if (foldedName.startsWith('twilight of the end - ')) {
    final slot = name.split(' - ').last;
    return RecipeBookItemPurpose(
      kind: 'Edania accessory material',
      description: 'A slot-specific Edania accessory material.',
      uses: <String>[
        'Crafts the $slot versions of Causality Shardstone and Apeiron.',
      ],
    );
  }
  if (foldedName.startsWith('apeiron ')) {
    return RecipeBookItemPurpose(
      kind: 'Accessory',
      description:
          'An Edania accessory that uses another unenhanced copy of the same slot as enhancement material.',
      uses: <String>[
        'Equip it in its matching accessory slot.',
        'Use an unenhanced copy of the same Apeiron accessory to enhance it.',
      ],
      notes: const <String>[
        'Enhancement level decreases on failure; Cron Stones or a Causality Hammer can prevent the level drop.',
        'A failed enhancement reduces Max Durability by 20.',
      ],
    );
  }
  if (foldedName.endsWith(' origin shard')) {
    final tier = name.split(' ').first;
    return RecipeBookItemPurpose(
      kind: 'Edania crystal material',
      description:
          'A tier-specific shard used to make the $tier Wandering Origin Crystal.',
    );
  }
  if (foldedName.startsWith('han reforge stone - ')) {
    final effect = _hanReforgeEffects[foldedName];
    return RecipeBookItemPurpose(
      kind: 'HAN Reforge Stone',
      description:
          'A high-grade reforge stone that applies one selected weapon reforge effect.',
      effects: effect == null ? const <String>[] : <String>[effect],
      uses: const <String>[
        'Use it through Item Reforge; up to 5 different reforge effects can be active.',
      ],
      notes: const <String>[
        'Applying it replaces the lower-grade effect of the same type.',
      ],
    );
  }
  if (foldedName.startsWith('reforge stone - ')) {
    return const RecipeBookItemPurpose(
      kind: 'Reforge Stone',
      description:
          'A weapon reforge stone and the matching base material for a HAN Reforge Stone.',
      uses: <String>[
        'Applies its named effect through Item Reforge.',
        'Heat 5 copies with Edania materials to make the matching HAN version.',
      ],
    );
  }
  if (foldedName.startsWith('embers of ynix - ')) {
    final slot = name.split(' - ').last;
    return RecipeBookItemPurpose(
      kind: 'Godslayer exchange material',
      description: 'A $slot-part material from Edania Godslayer content.',
      uses: <String>[
        'Exchange 100 with the Ynix Remnant for the matching Edana Godslayer box.',
      ],
    );
  }
  if (foldedName.startsWith('edana - godslayer') &&
      foldedName.endsWith(' box')) {
    return const RecipeBookItemPurpose(
      kind: 'Godslayer armor box',
      description: 'A box containing its named Edana Godslayer armor part.',
      uses: <String>['Open it to obtain the matching Godslayer armor part.'],
    );
  }
  if (_edaniaWorkshopCrates.contains(foldedName)) {
    return const RecipeBookItemPurpose(
      kind: 'Worker trade crate',
      description:
          'A regional trade crate made by workers in a Mineral Workshop.',
      notes: <String>['This is worker crafting, not character Processing.'],
    );
  }
  return switch (foldedName) {
    'fusion shard' => const RecipeBookItemPurpose(
      kind: 'Crystal material',
      description: 'An Edania material for Fused Crystal of Decimation.',
    ),
    "nev's fragment" => const RecipeBookItemPurpose(
      kind: 'Reforge material',
      description: 'An Edania material used in every HAN Reforge Stone.',
      uses: <String>['Crafts HAN Reforge Stones.'],
    ),
    "margahan's artifact" => const RecipeBookItemPurpose(
      kind: 'Artifact',
      description: 'A Life Skill Artifact with two Lightstone slots.',
      uses: <String>[
        'Equip it in an Artifact slot and infuse Lightstones for additional effects.',
      ],
    ),
    "margahan's fragment" => const RecipeBookItemPurpose(
      kind: 'Artifact material',
      description: "A principal material for Margahan's Artifact.",
    ),
    'olivine ore' => const RecipeBookItemPurpose(
      kind: 'Ore',
      description: 'A green Edania ore used to make Magical Olivine Powder.',
    ),
    'magical olivine powder' => const RecipeBookItemPurpose(
      kind: 'Life consumable material',
      description: 'A refined Edania alchemy material.',
      uses: <String>['Crafts Perfume of Verdure and Viridian Draught.'],
    ),
    'rough marble' => const RecipeBookItemPurpose(
      kind: 'Stone material',
      description:
          'Raw Edania marble used for Polished Marble and trade crates.',
    ),
    'polished marble' => const RecipeBookItemPurpose(
      kind: 'Processed stone',
      description: 'Refined marble used for Pure Marble and Marble Crates.',
    ),
    'pure marble' => const RecipeBookItemPurpose(
      kind: 'Artifact material',
      description: "A purified stone material for Margahan's Artifact.",
    ),
    'magnetite ore' => const RecipeBookItemPurpose(
      kind: 'Ore',
      description:
          'Raw Edania ore used for Magnetite materials and trade crates.',
    ),
    'melted magnetite shard' => const RecipeBookItemPurpose(
      kind: 'Processed metal',
      description: 'Heated Magnetite Ore used to make Magnetite Ingots.',
    ),
    'magnetite ingot' => const RecipeBookItemPurpose(
      kind: 'Processed metal',
      description:
          'A refined Magnetite material used for Pure Magnetite Crystals and trade crates.',
    ),
    'pure magnetite crystal' => const RecipeBookItemPurpose(
      kind: 'Artifact material',
      description: "A purified metal material for Margahan's Artifact.",
    ),
    'dawn black stone' => const RecipeBookItemPurpose(
      kind: 'Kharazad enhancement material',
      description: 'A high-tier Kharazad enhancement stone.',
      uses: <String>['Enhances DEC (X) Kharazad accessories.'],
    ),
    _ => null,
  };
}

RecipeBookItemPurpose? _edaniaReformedAccessoryPurpose(String foldedName) {
  final family = foldedName.contains(' ekleta ')
      ? 'Ekleta'
      : foldedName.contains(' apeiron ')
      ? 'Apeiron'
      : null;
  if (family == null) return null;
  final prefix = foldedName.split(' ').first;
  final reform = _edaniaAccessoryReforms[prefix];
  if (reform == null) return null;
  return RecipeBookItemPurpose(
    kind: 'Reformed Edania accessory',
    description: 'An $family accessory reformed with ${reform.cup}.',
    effects: <String>[reform.effect],
    uses: <String>['Equip it in its matching accessory slot.'],
    notes: const <String>[
      'Extract with Refined Essence of Emotions to recover the original accessory and cup.',
    ],
  );
}

const Map<String, ({String cup, String effect})> _edaniaAccessoryReforms = {
  'dawnbound': (cup: 'Cup of Destined Dawn', effect: 'Max HP +300'),
  'moonhushed': (
    cup: 'Cup of Reticent Moonbeams',
    effect: 'All AP +3 and Max Stamina +100',
  ),
  'sunstarved': (
    cup: 'Cup of Callous Sun',
    effect: 'Max HP +125 and Critical Hit Extra Damage +3%',
  ),
  'duskborne': (
    cup: 'Cup of Burgeoning Dusk',
    effect: 'All AP +3 and All Damage Reduction +6',
  ),
};

const Set<String> _edaniaWorkshopCrates = <String>{
  'magnetite ore crate',
  'rough marble crate',
  'magnetite ingot crate',
  'marble crate',
};

const Map<String, String> _hanReforgeEffects = <String, String>{
  'han reforge stone - all ap': 'All AP +5',
  'han reforge stone - all accuracy': 'All Accuracy +9',
  'han reforge stone - all damage reduction': 'All Damage Reduction +7',
  'han reforge stone - all evasion': 'All Evasion +13',
  'han reforge stone - max hp': 'Max HP +300',
  'han reforge stone - critical hit rate': 'Critical Hit Rate +6%',
  'han reforge stone - back attack extra damage':
      'Back Attack Extra Damage +2.5%',
  'han reforge stone - down attack extra damage':
      'Down Attack Extra Damage +2.5%',
  'han reforge stone - air attack extra damage':
      'Air Attack Extra Damage +2.5%',
  'han reforge stone - critical hit extra damage':
      'Critical Hit Extra Damage +1.5%',
  "han reforge stone - black spirit's rage recovery":
      "Black Spirit's Rage Recovery +0.6%",
};

// Official Pearl Abyss patch notes are the primary source for the progression
// facts below. The exact recipes remain catalog-derived so the UI cannot drift
// from planner calculations.
final Map<String, RecipeBookItemPurpose>
_verifiedEffectPurposes = <String, RecipeBookItemPurpose>{
  'concentrated herbal juice': _recoveryPurpose(
    description: 'A lightweight resource-recovery drink.',
    effect: 'Recover 175 MP/WP/SP',
    cooldown: '5 sec',
  ),
  'highly concentrated herbal juice': _recoveryPurpose(
    description: 'A stronger lightweight resource-recovery drink.',
    effect: 'Recover 250 MP/WP/SP',
    cooldown: '5 sec',
  ),
  'energy potion (extra large)': _recoveryPurpose(
    description: 'A potion that restores character Energy.',
    effect: 'Recover 50 Energy',
    cooldown: '10 min',
  ),
  'grain juice': _recoveryPurpose(
    description: 'A lightweight HP-recovery drink.',
    effect: 'Recover 150 HP',
    cooldown: '3 sec',
  ),
  'herbal juice': _recoveryPurpose(
    description: 'A lightweight resource-recovery drink.',
    effect: 'Recover 125 MP/WP/SP',
    cooldown: '5 sec',
  ),
  'hp potion (small)': _recoveryPurpose(
    description: 'A basic HP potion.',
    effect: 'Recover 150 HP',
    cooldown: '3 sec',
  ),
  'hp potion (medium)': _recoveryPurpose(
    description: 'A basic HP potion.',
    effect: 'Recover 250 HP',
    cooldown: '3 sec',
  ),
  'mp potion (small)': _recoveryPurpose(
    description: 'A basic MP, WP, and SP potion.',
    effect: 'Recover 125 MP/WP/SP',
    cooldown: '6 sec',
  ),
  'mp potion (medium)': _recoveryPurpose(
    description: 'A basic MP, WP, and SP potion.',
    effect: 'Recover 175 MP/WP/SP',
    cooldown: '6 sec',
  ),
  'refined herbal juice': _recoveryPurpose(
    description: 'A high-grade lightweight resource-recovery drink.',
    effect: 'Recover 375 MP/WP/SP',
    cooldown: '5 sec',
  ),
  'whale tendon potion': RecipeBookItemPurpose(
    kind: 'Recovery consumable',
    description: 'An emergency recovery potion made from whale materials.',
    effects: <String>['Recover 1,200 HP', 'Recover 300 MP/WP/SP'],
    notes: <String>['Instant effect. Cooldown: 30 sec.'],
  ),
  'miraculous herbal medicine': RecipeBookItemPurpose(
    kind: 'Energy recovery consumable',
    description: 'A long-cooldown medicine for restoring character Energy.',
    effects: <String>['Recover 500 Energy', 'Energy Recovery +30'],
    notes: <String>['Buff duration: 60 min. Cooldown: 22 hr.'],
  ),
  'destruction spirit stone': _activeStonePurpose(
    kind: 'Spirit stone',
    description:
        'A charge-limited combat stone equipped in the alchemy-stone slot.',
    effects: <String>['All AP +6', 'All Accuracy +8'],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'guardian spirit stone': _activeStonePurpose(
    kind: 'Spirit stone',
    description:
        'A charge-limited defense stone equipped in the alchemy-stone slot.',
    effects: <String>[
      'All Damage Reduction +6',
      'All Evasion +8',
      'Max HP +110',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'life spirit stone': _activeStonePurpose(
    kind: 'Spirit stone',
    description:
        'A charge-limited Life Skill stone equipped in the alchemy-stone slot.',
    effects: <String>[
      'Alchemy/Cooking Time -1.1 sec',
      'Processing Success Rate +11%',
      'Gathering/Fishing Speed +2',
      'Gathering Item Drop Rate +10%',
    ],
    duration: '10 min',
    cooldown: '10 min',
  ),
  'wild spirit stone': _activeStonePurpose(
    kind: 'Spirit stone',
    description:
        'A charge-limited combat stone equipped in the alchemy-stone slot.',
    effects: <String>['All AP +6', 'All Accuracy +8'],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'imperfect alchemy stone of destruction': _activeStonePurpose(
    effects: <String>[
      'All AP +2',
      'All Accuracy +2',
      'Attack Speed +1%',
      'Casting Speed +1%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'imperfect alchemy stone of life': _activeStonePurpose(
    effects: <String>[
      'Alchemy/Cooking Time -0.5 sec',
      'Processing Success Rate +5%',
      'Weight Limit +15 LT',
      'Gathering/Fishing Speed +1',
      'Gathering Item Drop Rate +3%',
    ],
    duration: '10 min',
    cooldown: '10 min',
  ),
  'imperfect alchemy stone of protection': _activeStonePurpose(
    effects: <String>[
      'All Damage Reduction +2',
      'All Evasion +2',
      'Max HP +50',
      'All Resistance +1%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'resplendent alchemy stone of destruction': _activeStonePurpose(
    effects: <String>[
      'All AP +10',
      'All Accuracy +12',
      'Attack Speed +6%',
      'Casting Speed +6%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'resplendent alchemy stone of life': _activeStonePurpose(
    effects: <String>[
      'Alchemy/Cooking Time -1.7 sec',
      'Processing Success Rate +17%',
      'Weight Limit +90 LT',
      'Gathering/Fishing Speed +2',
      'Gathering Item Drop Rate +16%',
    ],
    duration: '10 min',
    cooldown: '10 min',
  ),
  'resplendent alchemy stone of protection': _activeStonePurpose(
    effects: <String>[
      'All Damage Reduction +10',
      'All Evasion +12',
      'Max HP +170',
      'All Resistance +6%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'shining alchemy stone of destruction': _activeStonePurpose(
    effects: <String>[
      'All AP +16',
      'All Accuracy +16',
      'Attack Speed +10%',
      'Casting Speed +10%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'shining alchemy stone of life': _activeStonePurpose(
    effects: <String>[
      'Alchemy/Cooking Time -2.5 sec',
      'Processing Success Rate +25%',
      'Weight Limit +120 LT',
      'Gathering/Fishing Speed +3',
      'Gathering Item Drop Rate +25%',
    ],
    duration: '10 min',
    cooldown: '10 min',
  ),
  'shining alchemy stone of protection': _activeStonePurpose(
    effects: <String>[
      'All Damage Reduction +16',
      'All Evasion +16',
      'Max HP +250',
      'All Resistance +8%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'splendid alchemy stone of destruction': _activeStonePurpose(
    effects: <String>[
      'All AP +13',
      'All Accuracy +14',
      'Attack Speed +8%',
      'Casting Speed +8%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  'splendid alchemy stone of life': _activeStonePurpose(
    effects: <String>[
      'Alchemy/Cooking Time -2 sec',
      'Processing Success Rate +20%',
      'Weight Limit +105 LT',
      'Gathering/Fishing Speed +3',
      'Gathering Item Drop Rate +20%',
    ],
    duration: '10 min',
    cooldown: '10 min',
  ),
  'splendid alchemy stone of protection': _activeStonePurpose(
    effects: <String>[
      'All Damage Reduction +13',
      'All Evasion +14',
      'Max HP +210',
      'All Resistance +7%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  "khan's heart: destruction": _activeStonePurpose(
    kind: "Khan's Heart",
    description:
        "A rechargeable Khan's Heart equipped in the alchemy-stone slot.",
    effects: <String>[
      'All AP +7',
      'All Accuracy +9',
      'Attack Speed +4%',
      'Casting Speed +4%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  "khan's heart: life": _activeStonePurpose(
    kind: "Khan's Heart",
    description:
        "A rechargeable Khan's Heart equipped in the alchemy-stone slot.",
    effects: <String>[
      'Life EXP +30%',
      'Alchemy/Cooking Time -1.3 sec',
      'Processing Success Rate +13%',
      'Weight Limit +70 LT',
      'Gathering/Fishing Speed +2',
      'Gathering Item Drop Rate +12%',
    ],
    duration: '10 min',
    cooldown: '10 min',
  ),
  "khan's heart: protection": _activeStonePurpose(
    kind: "Khan's Heart",
    description:
        "A rechargeable Khan's Heart equipped in the alchemy-stone slot.",
    effects: <String>[
      'All Damage Reduction +7',
      'All Evasion +9',
      'All Resistance +4%',
      'Max HP +130',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
  "vell's heart": _activeStonePurpose(
    kind: "Vell's Heart",
    description:
        "A rechargeable Vell's Heart equipped in the alchemy-stone slot.",
    effects: <String>[
      'All AP +8',
      'All Accuracy +10',
      'Attack Speed +5%',
      'Casting Speed +5%',
    ],
    duration: '5 min',
    cooldown: '5 min',
  ),
};

final Map<String, RecipeBookItemPurpose>
_exactPurposes = <String, RecipeBookItemPurpose>{
  'antidote elixir': const RecipeBookItemPurpose(
    kind: 'Recovery consumable',
    description: 'An instant status-removal remedy.',
  ),
  'elixir of burn removal': const RecipeBookItemPurpose(
    kind: 'Recovery consumable',
    description: 'An instant status-removal remedy.',
  ),
  'elixir of hemostasis': const RecipeBookItemPurpose(
    kind: 'Recovery consumable',
    description: 'An instant status-removal remedy.',
  ),
  'elixir of regeneration': const RecipeBookItemPurpose(
    kind: 'Sailor recovery item',
    description: 'A medicine for sick sailors.',
    uses: <String>['Use it through Manage Sailors at a Wharf.'],
  ),
  'griffon claw': const RecipeBookItemPurpose(
    kind: 'Hunting material',
    description: 'A hunting trophy obtained from Griffons.',
    uses: <String>['Used to make Griffon Elixir.'],
  ),
  'monkey blood': const RecipeBookItemPurpose(
    kind: 'Alchemy blood',
    description:
        'Animal blood obtained by hunting a Monkey and using Fluid Collecting.',
    uses: <String>[
      "Used for Wise Man's Blood, Elixir of Energy, and recipes that accept its blood group.",
    ],
  ),
  'worm blood': const RecipeBookItemPurpose(
    kind: 'Alchemy blood',
    description:
        'Animal blood obtained by hunting a Worm and using Fluid Collecting.',
    uses: <String>[
      "Used for Legendary Beast's Blood and recipes that accept its blood group.",
    ],
  ),
  "pilgrim's cracked stone": const RecipeBookItemPurpose(
    kind: 'Guild drilling material',
    description: 'A desert stone obtained with a Guild Drill.',
    uses: <String>[
      'Grind it to obtain 1-2 Sharp Black Crystal Shards or 1 Mass of Pure Magic.',
    ],
  ),
  "pilgrim's stone": const RecipeBookItemPurpose(
    kind: 'Guild drilling material',
    description: 'A desert stone obtained with a Guild Drill.',
    uses: <String>[
      'Grind it to obtain 2-5 Sharp Black Crystal Shards or 1 Mass of Pure Magic.',
    ],
  ),
  'polished opal': const RecipeBookItemPurpose(
    kind: 'Processing material',
    description: 'A processed opal made by Heating 5 Rough Opal.',
    uses: <String>['Used to make Brilliant Opal and Black Gem Fragment.'],
  ),
  'mysterious seed': const RecipeBookItemPurpose(
    kind: 'Farming conversion material',
    description:
        'A rare farming conversion material; the generic seed itself is not plantable.',
    uses: <String>[
      'Shake it with a crop-specific Special or Magical Seed or Hypha to make a plantable version of that crop.',
    ],
  ),
  'wild beehive': const RecipeBookItemPurpose(
    kind: 'Cooking and processing material',
    description:
        'A hunted beehive that can be ground into Cooking Honey or used in Honeycomb Cookies.',
  ),
  'snowfield cedar plywood': const RecipeBookItemPurpose(
    kind: 'Wood material',
    description:
        'Processed wood made by chopping Snowfield Cedar Timber directly.',
  ),
  "obsidian specter's energy": const RecipeBookItemPurpose(
    kind: 'Blackstar armor reform material',
    description:
        'A bound Elvia reform material for eligible Blackstar defense gear.',
    uses: <String>[
      'Reforms Blackstar defense gear into Obsidian Blackstar with 100% success.',
    ],
    notes: <String>[
      'DUO/TRI: Evasion +2 (+2), Damage Reduction +1, Max HP +30.',
      'TET: Evasion +2 (+2), Damage Reduction +2 (+2), Max HP +40. PRI and PEN gain no extra Obsidian stats.',
      'A blacksmith can extract the material again with a Mirror of Equilibrium.',
      'Cannot be registered on the Central Market.',
    ],
  ),
  "specter's energy": const RecipeBookItemPurpose(
    kind: 'Rare gear material',
    description: 'A rare monster-drop material used in Blackstar progression.',
    uses: <String>["Crafts Blackstar gear and Obsidian Specter's Energy."],
  ),
  "flawless herald's crystal": const RecipeBookItemPurpose(
    kind: 'Artifact reform material',
    description:
        "A reform crystal for Kabua's and eligible Dehkia's Artifacts.",
    uses: <String>[
      "Kabua's Heralding Artifact: Monster AP +3, Monster Damage Reduction +5, Max HP +250.",
      "Dehkia's Heralding Artifact: All AP +6, Max HP +250.",
    ],
    notes: <String>[
      'The reform crystal can be extracted with a Mirror of Equilibrium.',
    ],
  ),
  "herald's crystal": const RecipeBookItemPurpose(
    kind: 'Artifact reform material',
    description: "An Edania material used to make Flawless Herald's Crystal.",
  ),
  "kabua's heralding artifact": const RecipeBookItemPurpose(
    kind: 'Artifact',
    description:
        'A reformed Artifact with Monster AP +3, Monster Damage Reduction +5, and Max HP +250.',
    uses: <String>[
      'Equip it in an Artifact slot and infuse Lightstones for additional effects.',
    ],
    notes: <String>['Cannot be registered on the Central Market.'],
  ),
  "dehkia's heralding artifact - all damage reduction": const RecipeBookItemPurpose(
    kind: 'Artifact',
    description:
        'A reformed damage-reduction Artifact with All AP +6 and Max HP +250.',
    uses: <String>[
      'Equip it in an Artifact slot and infuse Lightstones for additional effects.',
    ],
    notes: <String>['Cannot be registered on the Central Market.'],
  ),
  "dehkia's heralding artifact - all evasion": const RecipeBookItemPurpose(
    kind: 'Artifact',
    description: 'A reformed evasion Artifact with All AP +6 and Max HP +250.',
    uses: <String>[
      'Equip it in an Artifact slot and infuse Lightstones for additional effects.',
    ],
    notes: <String>['Cannot be registered on the Central Market.'],
  ),
  'brimming essence of aether': const RecipeBookItemPurpose(
    kind: 'Alchemy stone material',
    description:
        'A catalyst for high-grade alchemy-stone growth and combination.',
    uses: <String>[
      'Attempts Growth on Destruction, Protection, or Life alchemy stones.',
      "Combines or separates Vell's Heart or Khan's Heart with a matching alchemy stone.",
    ],
  ),
  'faint essence of aether': const RecipeBookItemPurpose(
    kind: 'Alchemy stone material',
    description:
        'A Dark Rift material refined into Brimming Essence of Aether.',
    uses: <String>[
      'Makes Brimming Essence of Aether for alchemy-stone growth and combination.',
    ],
  ),
  'origin of dark hunger': const RecipeBookItemPurpose(
    kind: 'Enhancement Chance material',
    description: 'A Devour item used to raise an existing Enhancement Chance.',
    uses: <String>[
      'Devour it through the Black Spirit; the stack gained depends on your current Enhancement Chance.',
    ],
  ),
  'resplendent origin of dark hunger': const RecipeBookItemPurpose(
    kind: 'Enhancement Chance material',
    description: 'A high-tier Devour item for very large Enhancement Chances.',
    uses: <String>[
      'Devour it through the Black Spirit to add Enhancement Chance at the supported high-stack range.',
    ],
  ),
  'primordial glow crystal': const RecipeBookItemPurpose(
    kind: 'Shai weapon upgrade material',
    description:
        'The upgrade crystal for turning Sunset Artina Sol into Primordial Artina Sol.',
    uses: <String>[
      'Upgrades Sunset Artina Sol to Primordial grade, adding Monster AP +10 and enabling Primordial reforging.',
    ],
    notes: <String>[
      'Cannot be registered on the Central Market or extracted after use.',
    ],
  ),
  'flame of the primordial': const RecipeBookItemPurpose(
    kind: 'Sovereign weapon material',
    description: 'A Primordial flame gathered from Morning Light boss content.',
    uses: <String>[
      'Combine it with a matching PEN Blackstar weapon at the Bonghwang Statue to craft a Sovereign weapon.',
      'Also used to craft Primordial Glow Crystal.',
    ],
  ),
  'gem of twilight': const RecipeBookItemPurpose(
    kind: 'Sovereign weapon material',
    description: 'A warm Primordial gem refined from Caphras Stones.',
    uses: <String>[
      'Used with matching PEN Blackstar and Caphras Lv. 20 boss gear in a Sovereign weapon recipe.',
    ],
    notes: <String>['It can be heated back into 20,000 Caphras Stones.'],
  ),
  'gem of the primordial': const RecipeBookItemPurpose(
    kind: 'Sovereign sub-weapon material',
    description: 'A Primordial gem refined from Primordial Fragments.',
    uses: <String>[
      'Used with a PEN Blackstar sub-weapon and Gem of Twilight to craft a Sovereign sub-weapon.',
    ],
  ),
  'crystallized energy of endtimes': const RecipeBookItemPurpose(
    kind: 'Amplified Lightstone material',
    description: 'An Edania progression material for Amplified Lightstones.',
    uses: <String>[
      'Used with a normal Lightstone, Magical Shards, and Magical Lightstone Crystals to make its Amplified version.',
    ],
    notes: <String>[
      'Obtained from Edania monster zones and weekly Edania boss chests.',
    ],
  ),
  'cup of destined dawn': const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'A necklace reform cup for Kharazad, Ekleta, and Apeiron.',
    effects: <String>['Max HP +300'],
  ),
  'cup of callous sun': const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'A ring reform cup for Kharazad, Ekleta, and Apeiron.',
    effects: <String>['Max HP +125', 'Critical Hit Extra Damage +3%'],
  ),
  'cup of burgeoning dusk': const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'A belt reform cup for Kharazad, Ekleta, and Apeiron.',
    effects: <String>['All AP +3', 'All Damage Reduction +6'],
  ),
  'cup of reticent moonbeams': const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'An earring reform cup for Kharazad, Ekleta, and Apeiron.',
    effects: <String>['All AP +3', 'Max Stamina +100'],
  ),
  'cup of arid moonlight': const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'A reform cup for eligible necklaces.',
    uses: <String>['Adds Max HP +150 to an eligible necklace.'],
  ),
  'cup of a lonely cloud': const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'A reform cup for eligible rings.',
    uses: <String>['Adds Max HP +125 to an eligible ring.'],
  ),
  'cup of dwindling starlight': const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'A reform cup for eligible rings.',
    uses: <String>['Adds Critical Hit Damage +3% to an eligible ring.'],
  ),
  "cup of earth's sorrows": const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'A reform cup for eligible earrings.',
    uses: <String>['Adds All AP +3 to an eligible earring with 100% success.'],
  ),
  'cup of lone tide': const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'A reform cup for eligible belts.',
    uses: <String>[
      'Adds All Damage Reduction +6 to an eligible belt with 100% success.',
    ],
  ),
  'cup of tragic nightfall': const RecipeBookItemPurpose(
    kind: 'Accessory reform material',
    description: 'A reform cup for eligible belts.',
    uses: <String>['Adds All AP +3 to an eligible belt with 100% success.'],
  ),
  'ebenruth': const RecipeBookItemPurpose(
    kind: 'Ocean treasure component',
    description: "One of the two components for Ebenruth's Nol.",
    uses: <String>[
      "Combine it with a Symbol-Engraved Nol to make Ebenruth's Nol for a Carrack or Panokseon.",
    ],
  ),
  'breath of all creations': const RecipeBookItemPurpose(
    kind: 'Timed combat consumable',
    description:
        'A rare guild-boss consumable with one powerful temporary effect.',
    effects: <String>[
      'Possible effect: All AP +70',
      'Possible effect: All Damage Reduction +300',
      'Possible effect: Attack/Casting Speed +20%',
      'Possible effect: Movement Speed +20%, Jump +2 m, Fall Damage -50%',
    ],
    uses: <String>[
      'Provides one of four effects: All AP, All Damage Reduction, Attack/Casting Speed, or Movement utility.',
    ],
    notes: <String>[
      'Duration: 10 min. Shared cooldown: 240 min. Does not stack with Pure Black Stone.',
    ],
  ),
  'unstable nouver core': const RecipeBookItemPurpose(
    kind: 'Nouverikant outfit material',
    description: 'A crafting material for the Nouverikant outfit.',
    uses: <String>[
      'Used with Dormant Nouverikant gear and Cantarnia Crystals to make sealed Nouverikant outfit pieces.',
    ],
  ),
  "gauche rawr-rawr's heart": const RecipeBookItemPurpose(
    kind: 'Hunting weapon reform material',
    description:
        'A reform heart for high-grade Hunting matchlocks and sniper rifles.',
    uses: <String>[
      'Upgrades a Hunting Master Matchlock or Hunting Marni Sniper Rifle and adds Max Durability +50.',
    ],
  ),
  'damaged hide': const RecipeBookItemPurpose(
    kind: 'Handcraft material',
    description: 'A low-grade Hunting hide used in Handcraft Workshops.',
    uses: <String>['Crafts Handcraft Workshop trade items.'],
  ),
  "enlightened one's cotton fabric": const RecipeBookItemPurpose(
    kind: 'Special textile',
    description:
        'An alchemy-treated cotton fabric used in advanced workshop crafting.',
  ),
  'eonwood round': const RecipeBookItemPurpose(
    kind: 'Star of Nostos material',
    description: 'An ancient wood round condensed with time-worn energy.',
    uses: <String>[
      'Arrange it with the other treasure components to craft Star of Nostos.',
    ],
  ),
  'essence of life': const RecipeBookItemPurpose(
    kind: 'Star of Nostos material',
    description: 'A liquid condensed from the energy of living things.',
    uses: <String>[
      'Arrange it with the other treasure components to craft Star of Nostos.',
    ],
  ),
  'naturewoven hide': const RecipeBookItemPurpose(
    kind: 'Star of Nostos material',
    description: 'A hide condensed from resilient natural energy.',
    uses: <String>[
      'Arrange it with the other treasure components to craft Star of Nostos.',
    ],
  ),
  'ferocious leather': const RecipeBookItemPurpose(
    kind: 'Dragon Slayer weapon material',
    description: 'A high-grade leather blending hot and cold energies.',
    uses: <String>[
      "Crafts Hughol's Weapon, which is then used in the Dragon Slayer weapon recipe.",
    ],
  ),
  'mystical cleaning oil': const RecipeBookItemPurpose(
    kind: 'Dragon Slayer weapon material',
    description: 'A weapon-treatment oil infused with fiery energy.',
    uses: <String>[
      "Crafts Hughol's Weapon, which is then used in the Dragon Slayer weapon recipe.",
    ],
  ),
  'mythical powder': const RecipeBookItemPurpose(
    kind: 'Mythical Horse material',
    description:
        'A fine powder made from Royal Fern Root and Flower of Oblivion.',
    uses: <String>[
      'Crafts a Mythical Censer for a Mythical Horse awakening attempt.',
    ],
  ),
  'jewel of illusion': const RecipeBookItemPurpose(
    kind: 'Deboreka material',
    description: 'A rare gem left by an unidentified apparition.',
    uses: <String>['Manufacture a Deboreka Earring.'],
  ),
  'royal plume': const RecipeBookItemPurpose(
    kind: 'Tier 5 pet material',
    description: 'A mystical plume prepared for advanced pet training.',
    uses: <String>[
      'Take it to a Tier 5 pet trainer to promote an eligible Tier 4 pet.',
    ],
  ),
  'mutant loah flower neutralizer': const RecipeBookItemPurpose(
    kind: 'Padix Island utility item',
    description:
        'A solution that neutralizes Mutant Loah Flowers on Padix Island.',
    uses: <String>[
      'Use it on a Loah Flower Pot to weaken affected Cox Pirates.',
    ],
  ),
  'special honey jar': const RecipeBookItemPurpose(
    kind: 'Fairy summoning item',
    description: 'A fragrant jar used to attract a Fairy.',
    uses: <String>[
      'Place it at an Unstable Rift to interact with the Fairy system.',
    ],
  ),
  'marking reagent': const RecipeBookItemPurpose(
    kind: 'PvP utility item',
    description: 'A thrown reagent that reveals a concealed PvP target.',
    effects: <String>[
      'Prevents the target from hiding their name or concealing themselves.',
    ],
    notes: <String>['Duration: 5 min. Cooldown: 5 sec.'],
  ),
  'sturdy snow white stone': const RecipeBookItemPurpose(
    kind: 'Manor furniture material',
    description: 'A weather-resistant stone used in outdoor Manor furniture.',
    uses: <String>['Crafts supported Manor furniture.'],
  ),
  "taebaek's belt": const RecipeBookItemPurpose(
    kind: 'Accessory with active skill',
    description:
        'An equipable belt that unlocks the Blessing of Taebaek skill.',
    effects: <String>[
      'Self: All AP +5 to +30 and All DP +10 to +50, based on enhancement level',
      'Self and allies: All Accuracy +0% to +5%',
      'Super Armor while using the skill',
    ],
    notes: <String>[
      'Skill duration: 60 sec. Cooldown: 10 min.',
      'The belt cannot be unequipped during the skill cooldown.',
    ],
  ),
  'flame of despair': const RecipeBookItemPurpose(
    kind: 'Slumbering Origin material',
    description: "The core material for crafting Fallen God's Armor.",
    uses: <String>["Upgrades PEN boss chest armor into Fallen God's Armor."],
  ),
  "edana's black stone": const RecipeBookItemPurpose(
    kind: 'Edana gear enhancement material',
    description: 'An enhancement stone for Edana defense gear.',
    uses: <String>['Enhances eligible Edana defense gear.'],
  ),
  'ocean horizon key': const RecipeBookItemPurpose(
    kind: 'Manor treasure key',
    description:
        'A key that opens the treasure chest for the Fountain of Blessed Springs manor furniture.',
  ),
  'origin of serni': const RecipeBookItemPurpose(
    kind: 'Sea Crystal material',
    description:
        'A processing material used to raise a Sea Crystal to the Zulatia grade.',
    uses: <String>[
      'Simple Alchemy: combine 10 with Oquilla Aquamarine Fresh Water and a Void Sea Crystal to make a Zulatia Crystal.',
    ],
  ),
  "dawn's aura": const RecipeBookItemPurpose(
    kind: 'Essence of Dawn catalyst',
    description: 'A catalyst carrying a trace of Dawn energy.',
    uses: <String>[
      'Heat it with a supported TET or PEN accessory to obtain Essence of Dawn.',
    ],
  ),
  'essence of ascent - accessory': const RecipeBookItemPurpose(
    kind: 'Tuvala accessory enhancement material',
    description: 'A late-stage Tuvala accessory progression material.',
    uses: <String>[
      'A non-season character can use it through the Black Spirit to enhance a supported PEN Tuvala accessory to HEX.',
    ],
  ),
  'melody of the stars': const RecipeBookItemPurpose(
    kind: 'Rare accessory byproduct',
    description:
        'A material recovered by heating certain enhanced blue-grade accessories.',
    uses: <String>[
      "Crafts Vaha's Dawn, the Mythical Censer, and Musical Spirit Wall Lamp.",
    ],
  ),
  "vell's fine powder": const RecipeBookItemPurpose(
    kind: 'Alchemy stone material',
    description:
        "A sea-boss material used in Vell's Heart and alchemy-stone recipes.",
    uses: <String>[
      "Recharges Vell's Heart, Khan's Heart, and ordinary alchemy stones.",
    ],
  ),
  'terrashard': const RecipeBookItemPurpose(
    kind: 'Star of Nostos material',
    description: 'A crystal condensed from deep-earth energy.',
    uses: <String>[
      'Arrange it with the other treasure components to craft Star of Nostos.',
    ],
  ),
  'wildsoul': const RecipeBookItemPurpose(
    kind: 'Star of Nostos material',
    description: 'A crystal condensed from resilient wild energy.',
    uses: <String>[
      'Arrange it with the other treasure components to craft Star of Nostos.',
    ],
  ),
  'trace of despair': const RecipeBookItemPurpose(
    kind: 'Legacy Trace material',
    description:
        'A retired gear material that is no longer required for crafting.',
    uses: <String>['Exchange it with the Black Spirit for Trace of Nature.'],
  ),
  'gale black stone': const RecipeBookItemPurpose(
    kind: 'Race Horse gear enhancement material',
    description: 'An enhancement stone for Giorgiaro Race Horse gear.',
    uses: <String>[
      'Enhances Giorgiaro champron, barding, saddle, stirrups, and horseshoe.',
    ],
  ),
  'citron tea': const RecipeBookItemPurpose(
    kind: 'Climate recovery drink',
    description: 'An Everfrost drink that cures Frostbite.',
    effects: <String>['Cures Frostbite'],
    notes: <String>['Instant effect. Cooldown: 5 sec.'],
  ),
  'star anise tea': const RecipeBookItemPurpose(
    kind: 'Climate recovery drink',
    description: 'A desert drink that restores body temperature.',
    effects: <String>['Cures Hypothermia'],
    notes: <String>['Instant effect.'],
  ),
  'spirit essence of earth': const RecipeBookItemPurpose(
    kind: 'Training food',
    description:
        'A Spirit Stone drink that grants Strength EXP and a defensive buff.',
    effects: <String>['All Damage Reduction +5', 'Gain Strength EXP'],
    notes: <String>['Duration: 30 min. Cooldown: 30 min.'],
  ),
  'spirit essence of water': const RecipeBookItemPurpose(
    kind: 'Training food',
    description: 'A Spirit Stone drink that grants Health EXP and Max HP.',
    effects: <String>['Max HP +100', 'Gain Health EXP'],
    notes: <String>['Duration: 30 min. Cooldown: 30 min.'],
  ),
  'spirit essence of wind': const RecipeBookItemPurpose(
    kind: 'Training food',
    description: 'A Spirit Stone drink that grants Breath EXP and speed.',
    effects: <String>['Attack Speed +1', 'Casting Speed +1', 'Gain Breath EXP'],
    notes: <String>['Duration: 30 min. Cooldown: 30 min.'],
  ),
  'splendid spirit stone of destruction': const RecipeBookItemPurpose(
    kind: 'Combat spirit stone',
    description:
        'A charge-limited spirit stone activated from the alchemy-stone slot.',
    effects: <String>[
      'All AP +13',
      'All Accuracy +14',
      'Attack Speed +8%',
      'Casting Speed +8%',
    ],
    notes: <String>['Duration: 5 min. Cooldown: 5 min.'],
  ),
  'sturdy whale tendon potion': const RecipeBookItemPurpose(
    kind: 'Recovery item',
    description: 'A high-grade emergency potion for hunters.',
    effects: <String>['Recover 3,000 HP', 'Recover 750 MP/WP/SP'],
    notes: <String>['Instant effect. Cooldown: 30 sec.'],
  ),
  'superior whale tendon potion': const RecipeBookItemPurpose(
    kind: 'Recovery item',
    description: 'A high-grade emergency potion for hunters.',
    effects: <String>['Recover 1,800 HP', 'Recover 500 MP/WP/SP'],
    notes: <String>['Instant effect. Cooldown: 30 sec.'],
  ),
  'iridescent maehwa liquor': const RecipeBookItemPurpose(
    kind: 'Long-cooldown buff drink',
    description: 'A potent Maehwa liquor with defensive effects.',
    effects: <String>[
      'All Damage Reduction +5',
      'All Resistance +5%',
      'Max HP +150',
    ],
    notes: <String>[
      'Duration: 30 min. Cooldown: 22 hr.',
      'Cannot be used together with Miraculous Nourishing Soup.',
    ],
  ),
  'refined grain juice': const RecipeBookItemPurpose(
    kind: 'Recovery item',
    description: 'A lightweight HP recovery drink.',
    effects: <String>['Recover 550 HP'],
    notes: <String>['Instant effect. Cooldown: 3 sec.'],
  ),
  'refined grain wine': const RecipeBookItemPurpose(
    kind: 'Cooking material',
    description:
        'A repeatedly distilled grain alcohol used as a cooking material.',
  ),
  "elion's tear": const RecipeBookItemPurpose(
    kind: 'Revival item',
    description: 'A consumable that revives your character after death.',
    uses: <String>['Revive immediately at the place of death.'],
  ),
};

RecipeBookItemPurpose _recoveryPurpose({
  required String description,
  required String effect,
  required String cooldown,
}) => RecipeBookItemPurpose(
  kind: 'Recovery consumable',
  description: description,
  effects: <String>[effect],
  notes: <String>['Instant effect. Cooldown: $cooldown.'],
);

RecipeBookItemPurpose _activeStonePurpose({
  String kind = 'Alchemy stone',
  String description =
      'A rechargeable alchemy stone equipped in the alchemy-stone slot.',
  required List<String> effects,
  required String duration,
  required String cooldown,
}) => RecipeBookItemPurpose(
  kind: kind,
  description: description,
  effects: effects,
  uses: const <String>[
    'Equip it in the alchemy-stone slot, then press U to activate its effects.',
  ],
  notes: <String>['Duration: $duration. Cooldown: $cooldown.'],
);

RecipeBookItemPurpose? _jetinaReformStonePurpose(
  String name,
  String foldedName,
) {
  if (!foldedName.startsWith('resplendent ') ||
      !foldedName.contains(' reform stone ')) {
    return null;
  }
  final match = RegExp(
    r' reform stone (i|ii|iii|iv|v)$',
  ).firstMatch(foldedName);
  if (match == null) return null;
  final stage = match.group(1)!.toUpperCase();
  final target = name
      .replaceFirst(RegExp(r'^Resplendent ', caseSensitive: false), '')
      .replaceFirst(
        RegExp(r' Reform Stone (I|II|III|IV|V)$', caseSensitive: false),
        '',
      );
  return RecipeBookItemPurpose(
    kind: 'Jetina boss gear reform material',
    description: 'Stage $stage reform stone for $target.',
    uses: <String>[
      stage == 'V'
          ? "Completes Jetina's guaranteed PEN boss-gear reform for $target."
          : "Advances $target through Jetina's guaranteed PEN boss-gear reform path.",
    ],
  );
}

RecipeBookItemPurpose? _combinedAlchemyStonePurpose(
  String name,
  String foldedName,
) {
  final match = RegExp(
    r"^(resplendent|splendid|shining) "
    r"(vell's heart|khan's heart: (destruction|life|protection))$",
  ).firstMatch(foldedName);
  if (match == null) return null;

  final grade = match.group(1)!;
  final isVell = match.group(2) == "vell's heart";
  final role = isVell ? 'destruction' : match.group(3)!;
  final baseStone = _verifiedEffectPurposes['$grade alchemy stone of $role'];
  if (baseStone == null) return null;

  final equippedEffect = isVell
      ? 'Displayed AP +3 (while equipped)'
      : switch (role) {
          'destruction' => 'Displayed AP +2 (while equipped)',
          'protection' => 'Displayed DP +2 (while equipped)',
          _ => 'All Life Skill Mastery +25 (while equipped)',
        };
  final displayRole = _titleCase(role);
  return RecipeBookItemPurpose(
    kind: 'Combined alchemy stone',
    description:
        '$name combines a ${_titleCase(grade)} $displayRole alchemy stone with '
        "${isVell ? "Vell's Heart" : "Khan's Heart"}.",
    effects: <String>[
      equippedEffect,
      if (!isVell && role == 'life') 'Life EXP +30%',
      ...baseStone.effects,
    ],
    uses: <String>[
      'Equip it for the heart item effect, then press U to activate the listed timed effects.',
    ],
    notes: <String>[
      ...baseStone.notes,
      'It can be separated again with Brimming Essence of Aether if the stone has not been upgraded.',
    ],
  );
}

RecipeBookItemPurpose? _plantableSeedPurpose(String name, String foldedName) {
  final match = RegExp(r'^(magical|special) (.+) seed$').firstMatch(foldedName);
  if (match == null) return null;

  final grade = match.group(1)!;
  final displayCrop = name
      .replaceFirst(RegExp(r'^(Magical|Special) '), '')
      .replaceFirst(RegExp(r' Seed$'), '');
  final grids = grade == 'magical' ? 5 : 1;
  return RecipeBookItemPurpose(
    kind: 'Plantable seed',
    description: 'A plantable ${_titleCase(grade)} seed for $displayCrop.',
    uses: <String>[
      'Plant it in a fenced garden to grow $displayCrop ($grids grid${grids == 1 ? '' : 's'}).',
    ],
  );
}

RecipeBookItemPurpose? _qualityFarmMaterialPurpose(String foldedName) {
  if (!_verifiedQualityFarmMaterials.contains(foldedName)) return null;

  return const RecipeBookItemPurpose(
    kind: 'Farming ingredient',
    description:
        'A higher-grade Farming product obtained through Farming or Plant Breeding.',
    uses: <String>['Used as a higher-grade ingredient in Cooking or Alchemy.'],
  );
}

const Set<String> _verifiedQualityFarmMaterials = <String>{
  'high-quality amanita mushroom',
  'high-quality ancient mushroom',
  'high-quality arrow mushroom',
  'high-quality bluffer mushroom',
  'high-quality chanterelle',
  'high-quality cloud mushroom',
  'high-quality dictyophora',
  'high-quality dwarf mushroom',
  'high-quality emperor mushroom',
  'high-quality fortune teller mushroom',
  'high-quality garlic',
  'high-quality ghost mushroom',
  'high-quality grape',
  'high-quality hot pepper',
  'high-quality hump mushroom',
  'high-quality mesima',
  'high-quality napa cabbage',
  'high-quality olive',
  'high-quality onion',
  'high-quality paprika',
  'high-quality pumpkin',
  'high-quality radish',
  'high-quality red-spotted amanita',
  'high-quality sky mushroom',
  'high-quality strawberry',
  'high-quality sunflower',
  'high-quality tiger mushroom',
  'high-quality tomato',
  'special chanterelle',
  'special dictyophora',
  'special fortune teller mushroom',
  'special garlic',
  'special grape',
  'special hot pepper',
  'special mesima',
  'special napa cabbage',
  'special olive',
  'special onion',
  'special paprika',
  'special pepper',
  'special pumpkin',
  'special radish',
  'special red-spotted amanita',
  'special strawberry',
  'special sunflower',
  'special tomato',
};

// These cards intentionally show the unenhanced (+0) item rather than an
// enhancement table. The base combat stats and built-in/set effects were
// checked against the current item records. The four defensive accessories
// below also include Pearl Abyss's February 2026 AP-penalty rebalance.
final Map<String, RecipeBookItemPurpose>
_exactEquipmentPurposes = <String, RecipeBookItemPurpose>{
  "ancient guardian's seal": _equipmentPurpose(
    kind: 'Necklace accessory',
    description:
        'An offensive necklace that forms the Ancient Weapon set with Ancient Weapon Core.',
    effects: <String>[
      'At +0: AP 6, DP 3, Accuracy 4',
      'Ancient Weapon 2-set: All Accuracy +20',
    ],
    equipUse: 'Equip it in a necklace slot.',
  ),
  'ancient weapon core': _equipmentPurpose(
    kind: 'Belt accessory',
    description:
        "A mixed-stat belt that forms the Ancient Weapon set with Ancient Guardian's Seal.",
    effects: <String>[
      'At +0: AP 4, DP 4, Accuracy 2',
      'Weight Limit +60 LT',
      'Ancient Weapon 2-set: All Accuracy +20',
    ],
    equipUse: 'Equip it in the belt slot.',
  ),
  "basilisk's belt": _equipmentPurpose(
    kind: 'Belt accessory',
    description: 'An offensive belt with extra carrying capacity.',
    effects: <String>['At +0: AP 5, Accuracy 2', 'Weight Limit +80 LT'],
    equipUse: 'Equip it in the belt slot.',
  ),
  'belt of shultz the gladiator': _equipmentPurpose(
    kind: 'Belt accessory',
    description:
        'An offensive utility belt with Stamina and carrying capacity.',
    effects: <String>[
      'At +0: AP 3, Accuracy 2',
      'Max Stamina +50',
      'Weight Limit +60 LT',
    ],
    equipUse: 'Equip it in the belt slot.',
  ),
  "bensho's necklace": _equipmentPurpose(
    kind: 'Necklace accessory',
    description:
        'A defensive necklace built around evasion and damage reduction, with a large AP penalty.',
    effects: <String>[
      'At +0: DP 10, Accuracy 4 (Evasion 5 (+10), Damage Reduction 5)',
      'All AP -60',
    ],
    equipUse: 'Equip it in a necklace slot.',
  ),
  'blue coral earring': _equipmentPurpose(
    kind: 'Earring accessory',
    description: 'An offensive earring with extra class resource capacity.',
    effects: <String>['At +0: AP 4, Accuracy 2', 'Max MP/WP/SP +25'],
    equipUse: 'Equip it in an earring slot.',
  ),
  'blue coral ring': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'An offensive ring with extra class resource capacity.',
    effects: <String>['At +0: AP 5, Accuracy 2', 'Max MP/WP/SP +25'],
    equipUse: 'Equip it in a ring slot.',
  ),
  'blue whale molar earring': _equipmentPurpose(
    kind: 'Earring accessory',
    description: 'An offensive earring with additional Max HP.',
    effects: <String>['At +0: AP 5, Accuracy 2', 'Max HP +100'],
    equipUse: 'Equip it in an earring slot.',
  ),
  'eye of the ruins ring': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'An offensive ring whose Max HP rises with enhancement.',
    effects: <String>['At +0: AP 5, Accuracy 2', 'Max HP +100'],
    equipUse: 'Equip it in a ring slot.',
  ),
  'forest ronaros ring': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'An offensive ring with AP and Accuracy.',
    effects: <String>['At +0: AP 5, Accuracy 2'],
    equipUse: 'Equip it in a ring slot.',
  ),
  "fugitive khalk's earring": _equipmentPurpose(
    kind: 'Earring accessory',
    description:
        'An offensive earring with extra Stamina and class resource capacity.',
    effects: <String>[
      'At +0: AP 5, Accuracy 2',
      'Max Stamina +50',
      'Max MP/WP/SP +50',
    ],
    equipUse: 'Equip it in an earring slot.',
  ),
  'gartner belt': _equipmentPurpose(
    kind: 'Belt accessory',
    description: 'A defensive utility belt with Max HP and carrying capacity.',
    effects: <String>['At +0: Accuracy 2', 'Max HP +50', 'Weight Limit +50 LT'],
    equipUse: 'Equip it in the belt slot.',
  ),
  'kagtum submission ring': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'An offensive ring with a small PvE damage bonus.',
    effects: <String>[
      'At +0: AP 5, Accuracy 2',
      'Extra AP Against Monsters +1',
    ],
    equipUse: 'Equip it in a ring slot.',
  ),
  'mark of shadow': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'An offensive ring with AP and Accuracy.',
    effects: <String>['At +0: AP 5, Accuracy 2'],
    equipUse: 'Equip it in a ring slot.',
  ),
  'mesto earring': _equipmentPurpose(
    kind: 'Earring accessory',
    description: 'An offensive earring with higher base Accuracy.',
    effects: <String>['At +0: AP 4, Accuracy 6'],
    equipUse: 'Equip it in an earring slot.',
  ),
  'narc ear accessory': _equipmentPurpose(
    kind: 'Earring accessory',
    description:
        'An offensive earring specialized for fighting Kamasylvian monsters.',
    effects: <String>[
      'At +0: AP 5, Accuracy 2',
      'Extra AP Against Kamasylvian Monsters +3',
    ],
    equipUse: 'Equip it in an earring slot.',
  ),
  'necklace of good deeds': _equipmentPurpose(
    kind: 'Necklace accessory',
    description: 'An offensive necklace with unusually high base Accuracy.',
    effects: <String>['At +0: AP 6, Accuracy 16'],
    equipUse: 'Equip it in a necklace slot.',
  ),
  'necklace of shultz the gladiator': _equipmentPurpose(
    kind: 'Necklace accessory',
    description: 'An offensive necklace with AP and Accuracy.',
    effects: <String>['At +0: AP 7, Accuracy 2'],
    equipUse: 'Equip it in a necklace slot.',
  ),
  'nert ring': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'An accuracy-focused ring with additional Max HP.',
    effects: <String>['At +0: Accuracy 6', 'Max HP +25'],
    equipUse: 'Equip it in a ring slot.',
  ),
  "orkinrad's belt": _equipmentPurpose(
    kind: 'Belt accessory',
    description: 'An offensive belt with extra carrying capacity.',
    effects: <String>['At +0: AP 7, Accuracy 2', 'Weight Limit +80 LT'],
    equipUse: 'Equip it in the belt slot.',
  ),
  "outlaw's ring": _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'A mixed offensive and defensive ring with extra Stamina.',
    effects: <String>[
      'At +0: AP 3, DP 4, Accuracy 2 (Damage Reduction 4)',
      'Max Stamina +50',
    ],
    equipUse: 'Equip it in a ring slot.',
  ),
  'rainbow coral ring': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'An offensive ring with additional Max HP.',
    effects: <String>['At +0: AP 5, Accuracy 2', 'Max HP +100'],
    equipUse: 'Equip it in a ring slot.',
  ),
  'red coral earring': _equipmentPurpose(
    kind: 'Earring accessory',
    description: 'An accuracy-focused earring with extra Stamina.',
    effects: <String>['At +0: AP 2, Accuracy 14', 'Max Stamina +50'],
    equipUse: 'Equip it in an earring slot.',
  ),
  'red coral ring': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'A mixed offensive and defensive ring with extra Stamina.',
    effects: <String>[
      'At +0: AP 4, DP 3, Accuracy 2 (Damage Reduction 3)',
      'Max Stamina +50',
    ],
    equipUse: 'Equip it in a ring slot.',
  ),
  'rhutum belt': _equipmentPurpose(
    kind: 'Belt accessory',
    description: 'A basic carrying-capacity belt.',
    effects: <String>['At +0: Accuracy 2', 'Weight Limit +60 LT'],
    equipUse: 'Equip it in the belt slot.',
  ),
  'rhutum elite belt': _equipmentPurpose(
    kind: 'Belt accessory',
    description: 'A defensive belt with extra carrying capacity.',
    effects: <String>[
      'At +0: DP 4, Accuracy 2 (Damage Reduction 4)',
      'Weight Limit +60 LT',
    ],
    equipUse: 'Equip it in the belt slot.',
  ),
  'ridell earring': _equipmentPurpose(
    kind: 'Earring accessory',
    description:
        'A defensive, accuracy-focused earring with a substantial AP penalty.',
    effects: <String>[
      'At +0: DP 5, Accuracy 6 (Damage Reduction 5)',
      'All AP -30',
    ],
    equipUse: 'Equip it in an earring slot.',
  ),
  'ring of crescent guardian': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'An offensive ring with AP and Accuracy.',
    effects: <String>['At +0: AP 5, Accuracy 2'],
    equipUse: 'Equip it in a ring slot.',
  ),
  'scarla necklace': _equipmentPurpose(
    kind: 'Necklace accessory',
    description: 'A mixed offensive and defensive necklace.',
    effects: <String>['At +0: AP 5, DP 5, Accuracy 4 (Damage Reduction 5)'],
    equipUse: 'Equip it in a necklace slot.',
  ),
  "serap's necklace": _equipmentPurpose(
    kind: 'Necklace accessory',
    description: 'An offensive necklace with additional Max HP.',
    effects: <String>['At +0: AP 8, Accuracy 4', 'Max HP +50'],
    equipUse: 'Equip it in a necklace slot.',
  ),
  'shrine guardian token': _equipmentPurpose(
    kind: 'Ring accessory',
    description: 'A defensive ring with Max HP and a substantial AP penalty.',
    effects: <String>[
      'At +0: DP 5, Accuracy 2 (Damage Reduction 5)',
      'Max HP +20',
      'All AP -30',
    ],
    equipUse: 'Equip it in a ring slot.',
  ),
  "sicil's necklace": _equipmentPurpose(
    kind: 'Necklace accessory',
    description: 'A mixed AP and evasion necklace.',
    effects: <String>['At +0: AP 7, DP 3, Accuracy 4 (Evasion 3 (+6))'],
    equipUse: 'Equip it in a necklace slot.',
  ),
  'token of friendship': _equipmentPurpose(
    kind: 'Earring accessory',
    description:
        'A defensive earring with Max HP and a substantial AP penalty.',
    effects: <String>[
      'At +0: DP 5, Accuracy 2 (Damage Reduction 5)',
      'Max HP +20',
      'All AP -30',
    ],
    equipUse: 'Equip it in an earring slot.',
  ),
  'tree spirit belt': _equipmentPurpose(
    kind: 'Belt accessory',
    description:
        'An offensive, accuracy-focused belt with extra carrying capacity.',
    effects: <String>['At +0: AP 5, Accuracy 6', 'Weight Limit +80 LT'],
    equipUse: 'Equip it in the belt slot.',
  ),
  'tungrad belt': _equipmentPurpose(
    kind: 'Belt accessory',
    description:
        "An offensive belt that raises the holder's Black Spirit's Rage capacity.",
    effects: <String>[
      'At +0: AP 6, Accuracy 2',
      "Self-obtainable Black Spirit's Rage +20%",
      'Weight Limit +80 LT',
      "Tungrad 3-set: Self-obtainable Black Spirit's Rage +30%",
      'Tungrad 5-set: All AP +12',
    ],
    equipUse: 'Equip it in the belt slot.',
  ),
  'valtarra eclipsed belt': _equipmentPurpose(
    kind: 'Belt accessory',
    description: 'An offensive belt with extra carrying capacity.',
    effects: <String>['At +0: AP 5, Accuracy 2', 'Weight Limit +80 LT'],
    equipUse: 'Equip it in the belt slot.',
  ),
  "witch's earring": _equipmentPurpose(
    kind: 'Earring accessory',
    description: 'An offensive earring with AP and Accuracy.',
    effects: <String>['At +0: AP 5, Accuracy 2'],
    equipUse: 'Equip it in an earring slot.',
  ),
  "fortuna's luck armor": _fortunaPurpose(
    slot: 'armor',
    baseStats: 'At +0: DP 6 (Evasion 3 (+9), Damage Reduction 3)',
  ),
  "fortuna's luck shoes": _fortunaPurpose(
    slot: 'shoes',
    baseStats: 'At +0: DP 1 (Evasion 1 (+3))',
  ),
  "gloves of fortuna's luck": _fortunaPurpose(
    slot: 'gloves',
    baseStats: 'At +0: DP 1 (Evasion 1 (+3))',
  ),
  "helmet of fortuna's luck": _fortunaPurpose(
    slot: 'helmet',
    baseStats: 'At +0: DP 3 (Evasion 2 (+6), Damage Reduction 1)',
  ),
  'taritas armor': _taritasPurpose(
    slot: 'armor',
    baseStats: 'At +0: DP 8 (Evasion 5 (+15), Damage Reduction 3 (+3))',
    itemEffects: <String>['Max HP +20', 'Max MP/WP/SP +20'],
  ),
  'taritas gloves': _taritasPurpose(
    slot: 'gloves',
    baseStats:
        'At +0: DP 3, Accuracy 8 (Evasion 3 (+9), Damage Reduction 0 (+2))',
  ),
  'taritas helmet': _taritasPurpose(
    slot: 'helmet',
    baseStats: 'At +0: DP 5 (Evasion 4 (+12), Damage Reduction 1 (+2))',
    itemEffects: <String>['Knockback/Floating Resistance +15%'],
  ),
  'taritas shoes': _taritasPurpose(
    slot: 'shoes',
    baseStats: 'At +0: DP 4 (Evasion 4 (+12), Damage Reduction 0 (+2))',
  ),
  'krea battle axe': _kreaPurpose('battle axe'),
  'krea kyve': _kreaPurpose('kyve'),
  'krea longbow': _kreaPurpose('longbow'),
  'krea morning star': _kreaPurpose('morning star'),
  'krea serenaca': _kreaPurpose('serenaca'),
  'krea shamshir': _kreaPurpose('shamshir'),
  'krea staff': _kreaPurpose('staff'),
};

RecipeBookItemPurpose _equipmentPurpose({
  required String kind,
  required String description,
  required List<String> effects,
  required String equipUse,
}) => RecipeBookItemPurpose(
  kind: kind,
  description: description,
  effects: effects,
  uses: <String>[equipUse],
);

RecipeBookItemPurpose _fortunaPurpose({
  required String slot,
  required String baseStats,
}) => _equipmentPurpose(
  kind: 'Defense gear',
  description:
      "A Fortuna's Luck $slot; the set emphasizes Luck and Movement Speed.",
  effects: <String>[
    baseStats,
    'Fortuna 2-set: Luck +2',
    'Fortuna 3-set: Movement Speed +3',
  ],
  equipUse: 'Equip it in the $slot slot.',
);

RecipeBookItemPurpose _taritasPurpose({
  required String slot,
  required String baseStats,
  List<String> itemEffects = const <String>[],
}) => _equipmentPurpose(
  kind: 'Defense gear',
  description:
      'A Taritas $slot; the set emphasizes class resources and Accuracy.',
  effects: <String>[
    baseStats,
    ...itemEffects,
    'Taritas 2-set: Max MP/WP/SP +100',
    'Taritas 3-set: All Accuracy +20',
  ],
  equipUse: 'Equip it in the $slot slot.',
);

RecipeBookItemPurpose _kreaPurpose(String weapon) => _equipmentPurpose(
  kind: 'Main weapon',
  description: 'A two-slot Krea $weapon whose set bonus favors Accuracy.',
  effects: <String>['At +0: AP 17–19', 'Krea set: All Accuracy +20'],
  equipUse: "Equip it as a compatible class's main weapon.",
);

const Map<String, String> _artifactItemEffects = <String, String>{
  "kehelle's artifact - black spirit's rage max increase":
      "Black Spirit's Rage Max Increase +10%",
  "kehelle's artifact - max hp": 'Max HP +75',
  "kehelle's artifact - max stamina": 'Max Stamina +50',
  "lesha's artifact - all damage reduction": 'All Damage Reduction +3',
  "lesha's artifact - all evasion": 'All Evasion +6',
  "lesha's artifact - magic damage reduction": 'Magic Damage Reduction +6',
  "lesha's artifact - magic evasion": 'Magic Evasion +12',
  "lesha's artifact - melee damage reduction": 'Melee Damage Reduction +6',
  "lesha's artifact - melee evasion": 'Melee Evasion +12',
  "lesha's artifact - monster damage reduction": 'Monster Damage Reduction +9',
  "lesha's artifact - ranged damage reduction": 'Ranged Damage Reduction +6',
  "lesha's artifact - ranged evasion": 'Ranged Evasion +12',
  "marsh's artifact - extra ap against monsters":
      'Extra AP Against Monsters +6',
  "marsh's artifact - magic accuracy": 'Magic Accuracy +8',
  "marsh's artifact - magic ap": 'Magic AP +4',
  "marsh's artifact - melee accuracy": 'Melee Accuracy +8',
  "marsh's artifact - melee ap": 'Melee AP +4',
  "marsh's artifact - ranged accuracy": 'Ranged Accuracy +8',
  "marsh's artifact - ranged ap": 'Ranged AP +4',
  "sethra's artifact - alchemy exp": 'Alchemy EXP +5%',
  "sethra's artifact - alchemy mastery": 'Alchemy Mastery +10',
  "sethra's artifact - barter exp": 'Barter EXP +5%',
  "sethra's artifact - cooking exp": 'Cooking EXP +5%',
  "sethra's artifact - cooking mastery": 'Cooking Mastery +10',
  "sethra's artifact - farming exp": 'Farming EXP +5%',
  "sethra's artifact - fishing exp": 'Fishing EXP +5%',
  "sethra's artifact - fishing mastery": 'Fishing Mastery +10',
  "sethra's artifact - gathering exp": 'Gathering EXP +5%',
  "sethra's artifact - gathering item drop rate":
      'Gathering Item Drop Rate +2%',
  "sethra's artifact - gathering mastery": 'Gathering Mastery +10',
  "sethra's artifact - hunting exp": 'Hunting EXP +5%',
  "sethra's artifact - hunting mastery": 'Hunting Mastery +10',
  "sethra's artifact - life exp": 'Life EXP +3%',
  "sethra's artifact - life skill mastery": 'Life Skill Mastery +7',
  "sethra's artifact - mount exp": 'Mount EXP +3%',
  "sethra's artifact - processing exp": 'Processing EXP +5%',
  "sethra's artifact - processing mastery": 'Processing Mastery +10',
  "sethra's artifact - processing success rate": 'Processing Success Rate +5%',
  "sethra's artifact - sailing exp": 'Sailing EXP +5%',
  "sethra's artifact - sailing mastery": 'Sailing Mastery +10',
  "sethra's artifact - trading exp": 'Trading EXP +5%',
  "sethra's artifact - training exp": 'Training EXP +5%',
  "sethra's artifact - training mastery": 'Training Mastery +10',
};

String _derivedDescription({
  required String foldedName,
  required String kind,
  required String foldedMethod,
}) {
  final foldedKind = _fold(kind);

  if (foldedKind == 'dish') {
    return 'A cooked dish that provides a temporary food effect.';
  }
  if (foldedKind == 'cooking material') {
    return 'An ingredient used in cooking recipes.';
  }
  if (foldedKind == 'draught') {
    return 'A temporary combat draught.';
  }
  if (foldedKind == 'elixir') {
    return 'A temporary elixir buff.';
  }
  if (foldedKind == 'perfume') {
    return 'A temporary perfume buff.';
  }
  if (foldedKind == 'lightstone') {
    return 'A Lightstone infused into an Artifact for its listed effect.';
  }
  if (foldedKind == 'gear crystal') {
    return 'A crystal equipped through a crystal preset for its listed effect.';
  }
  if (foldedName.endsWith(' timber')) {
    return 'Raw wood that can be processed into planks.';
  }
  if (foldedName.endsWith(' plank')) {
    return 'Processed wood made by chopping timber.';
  }
  if (foldedName.endsWith(' plywood')) {
    if (foldedMethod == 'heating') {
      return 'A reinforced plywood material made through Heating.';
    }
    return 'Processed wood made by chopping planks.';
  }
  if (foldedName.contains('timber square') ||
      foldedName.contains('hard pillar')) {
    return 'A reinforced structural wood material.';
  }
  if (foldedName.endsWith(' ingot')) {
    return 'A refined metal crafting material.';
  }
  if (foldedName.endsWith(' dough')) {
    return 'Prepared cooking dough used as a recipe ingredient.';
  }
  if (foldedName.startsWith('trace of ')) {
    return 'A Trace material used in alchemy and equipment recipes.';
  }
  if (foldedName.contains('medicine') ||
      foldedName.contains('juice') ||
      foldedName.contains('potion')) {
    return 'A consumable item with a recovery or utility effect.';
  }
  if (foldedName.endsWith(' seed')) {
    return 'A farming seed used to grow the named crop.';
  }
  if (foldedName.endsWith(' hide') ||
      foldedName.endsWith(' leather') ||
      foldedName.endsWith(' fur') ||
      foldedName.endsWith(' plume') ||
      foldedName == 'wool') {
    return 'A hide, fur, plume, or textile material used in crafting.';
  }
  if (_looksLikeGem(foldedName)) {
    return 'A gemstone material used in processing and crafting.';
  }
  if (foldedKind == 'alchemy blood') {
    return 'A prepared alchemical blood used in advanced alchemy recipes.';
  }
  if (foldedKind == 'blood material') {
    return 'Animal blood used as an alchemy ingredient.';
  }
  if (foldedKind.contains('mushroom')) {
    return 'A mushroom used in alchemy and cooking recipes.';
  }
  if (foldedKind.contains('reagent')) {
    return 'A prepared reagent used in alchemy recipes.';
  }
  if (foldedKind.contains('oil')) {
    return 'A prepared alchemy oil used in advanced recipes.';
  }
  // A planner leaf, group label, or token in an item name is not evidence of
  // its in-game purpose. An empty description is preferable to a confident
  // but false explanation; verified recipe links and acquisition routes still
  // appear in the card.
  return '';
}

List<String> _derivedTerminalUses({required String kind}) {
  final foldedKind = _fold(kind);
  if (foldedKind == 'dish') {
    return const <String>['Consume it to gain its temporary food effect.'];
  }
  if (foldedKind == 'draught' ||
      foldedKind == 'elixir' ||
      foldedKind == 'perfume') {
    return const <String>['Consume it to activate the listed temporary buff.'];
  }
  if (foldedKind == 'gear crystal') {
    return const <String>[
      'Add it to a crystal preset to apply the listed stat effect.',
    ];
  }
  if (foldedKind == 'lightstone') {
    return const <String>[
      'Infuse it into an Artifact to apply the listed stat effect.',
    ];
  }
  if (foldedKind.contains('blood') ||
      foldedKind.contains('mushroom') ||
      foldedKind.contains('reagent') ||
      foldedKind.contains('oil')) {
    return const <String>['Used as an ingredient in alchemy recipes.'];
  }
  return const <String>[];
}

const Set<String> _knownAccessoryNames = <String>{
  "ancient guardian's seal",
  'ancient weapon core',
  'belt of shultz the gladiator',
  'mark of shadow',
  'narc ear accessory',
  'necklace of good deeds',
  'necklace of shultz the gladiator',
  'ring of crescent guardian',
  'shrine guardian token',
  'token of friendship',
};

bool _looksLikeAccessory(String foldedName) =>
    _knownAccessoryNames.contains(foldedName) ||
    RegExp(r'( ring| earring| belt| necklace)$').hasMatch(foldedName);

bool _looksLikeArmor(String foldedName) =>
    foldedName == "gloves of fortuna's luck" ||
    foldedName == "helmet of fortuna's luck" ||
    RegExp(r'( helmet| armor| gloves| shoes)$').hasMatch(foldedName);

bool _looksLikeWeapon(String foldedName) =>
    foldedName.startsWith('krea ') ||
    RegExp(
      r'( battle axe| kyve| longbow| morning star| serenaca| shamshir| staff)$',
    ).hasMatch(foldedName);

bool _isKnownNonGearKind(String foldedKind) =>
    foldedKind == 'draught' ||
    foldedKind == 'elixir' ||
    foldedKind == 'perfume' ||
    foldedKind == 'blessing' ||
    foldedKind == 'dish' ||
    foldedKind == 'cooking material' ||
    foldedKind.contains('crystal') ||
    foldedKind.contains('lightstone');

bool _looksLikeGem(String foldedName) => RegExp(
  r'(ruby|emerald|topaz|sapphire|diamond|lapis lazuli)$',
).hasMatch(foldedName);

String _fold(String value) => value.trim().toLowerCase();

String _titleCase(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
