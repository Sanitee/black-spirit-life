import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_purpose.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RecipeBookItemPurpose purposeFor(String name) => recipeBookItemPurposeFor(
    name: name,
    recipe: null,
    currentKind: '',
    hasCraftUses: false,
  );

  const residualEquipmentNames = <String>[
    "Ancient Guardian's Seal",
    'Ancient Weapon Core',
    "Basilisk's Belt",
    'Belt of Shultz the Gladiator',
    "Bensho's Necklace",
    'Blue Coral Earring',
    'Blue Coral Ring',
    'Blue Whale Molar Earring',
    'Eye of the Ruins Ring',
    'Forest Ronaros Ring',
    "Fortuna's Luck Armor",
    "Fortuna's Luck Shoes",
    "Fugitive Khalk's Earring",
    'Gartner Belt',
    "Gloves of Fortuna's Luck",
    "Helmet of Fortuna's Luck",
    'Kagtum Submission Ring',
    'Krea Battle Axe',
    'Krea Kyve',
    'Krea Longbow',
    'Krea Morning Star',
    'Krea Serenaca',
    'Krea Shamshir',
    'Krea Staff',
    'Mark of Shadow',
    'Mesto Earring',
    'Narc Ear Accessory',
    'Necklace of Good Deeds',
    'Necklace of Shultz the Gladiator',
    'Nert Ring',
    "Orkinrad's Belt",
    "Outlaw's Ring",
    'Rainbow Coral Ring',
    'Red Coral Earring',
    'Red Coral Ring',
    'Rhutum Belt',
    'Rhutum Elite Belt',
    'Ridell Earring',
    'Ring of Crescent Guardian',
    'Scarla Necklace',
    "Serap's Necklace",
    'Shrine Guardian Token',
    "Sicil's Necklace",
    'Taritas Armor',
    'Taritas Gloves',
    'Taritas Helmet',
    'Taritas Shoes',
    'Token of Friendship',
    'Tree Spirit Belt',
    'Tungrad Belt',
    'Valtarra Eclipsed Belt',
    "Witch's Earring",
  ];

  test('all 52 residual gear cards show concise unenhanced effects', () {
    expect(residualEquipmentNames, hasLength(52));

    for (final name in residualEquipmentNames) {
      final purpose = purposeFor(name);
      expect(purpose.description, isNotEmpty, reason: name);
      expect(purpose.effects, isNotEmpty, reason: name);
      expect(
        purpose.description.toLowerCase(),
        isNot(contains('gain its item stats')),
        reason: name,
      );
    }
  });

  test('current defensive-accessory AP penalties remain explicit', () {
    expect(purposeFor("Bensho's Necklace").effects, contains('All AP -60'));
    for (final name in <String>[
      'Ridell Earring',
      'Shrine Guardian Token',
      'Token of Friendship',
    ]) {
      expect(purposeFor(name).effects, contains('All AP -30'), reason: name);
    }
  });

  test(
    'set gear gives exact base and set effects without an upgrade table',
    () {
      expect(purposeFor('Krea Longbow').effects, <String>[
        'At +0: AP 17–19',
        'Krea set: All Accuracy +20',
      ]);
      expect(
        purposeFor("Fortuna's Luck Armor").effects,
        containsAll(<String>[
          'At +0: DP 6 (Evasion 3 (+9), Damage Reduction 3)',
          'Fortuna 2-set: Luck +2',
          'Fortuna 3-set: Movement Speed +3',
        ]),
      );
      expect(
        purposeFor('Taritas Helmet').effects,
        containsAll(<String>[
          'At +0: DP 5 (Evasion 4 (+12), Damage Reduction 1 (+2))',
          'Knockback/Floating Resistance +15%',
          'Taritas 2-set: Max MP/WP/SP +100',
          'Taritas 3-set: All Accuracy +20',
        ]),
      );
    },
  );

  test('special accessory roles include their important base effects', () {
    expect(
      purposeFor('Ancient Weapon Core').effects,
      containsAll(<String>[
        'At +0: AP 4, DP 4, Accuracy 2',
        'Weight Limit +60 LT',
        'Ancient Weapon 2-set: All Accuracy +20',
      ]),
    );
    expect(
      purposeFor('Narc Ear Accessory').effects,
      contains('Extra AP Against Kamasylvian Monsters +3'),
    );
    expect(
      purposeFor('Tungrad Belt').effects,
      containsAll(<String>[
        "Self-obtainable Black Spirit's Rage +20%",
        'Tungrad 5-set: All AP +12',
      ]),
    );
  });

  test('Edania accessories explain enhancement and reform behavior', () {
    final ekleta = purposeFor('Ekleta Necklace');
    expect(ekleta.kind, 'Ekleta accessory');
    expect(
      ekleta.notes,
      containsAll(<String>[
        'Each enhancement attempt consumes 1 Causality Shardstone - Necklace.',
        'A failed enhancement reduces Max Durability by 20.',
        'At PRI or higher, a Causality Hammer prevents the enhancement level from dropping on failure.',
      ]),
    );

    final reformed = purposeFor('Sunstarved Apeiron Ring');
    expect(reformed.kind, 'Reformed Edania accessory');
    expect(
      reformed.description,
      'An Apeiron accessory reformed with Cup of Callous Sun.',
    );
    expect(reformed.effects, <String>[
      'Max HP +125 and Critical Hit Extra Damage +3%',
    ]);
    expect(
      reformed.notes,
      contains(
        'Extract with Refined Essence of Emotions to recover the original accessory and cup.',
      ),
    );

    final cup = purposeFor('Cup of Callous Sun');
    expect(cup.description, contains('Kharazad, Ekleta, and Apeiron'));
    expect(
      cup.effects,
      containsAll(<String>['Max HP +125', 'Critical Hit Extra Damage +3%']),
    );
  });

  test('Edania reference items state their actual workflow', () {
    final crate = purposeFor('Magnetite Ore Crate');
    expect(crate.kind, 'Worker trade crate');
    expect(
      crate.notes,
      contains('This is worker crafting, not character Processing.'),
    );

    final embers = purposeFor('Embers of Ynix - Helmet');
    expect(embers.kind, 'Godslayer exchange material');
    expect(embers.uses.single, contains('Exchange 100'));

    final box = purposeFor("Edana - Godslayer's Courage Box");
    expect(box.kind, 'Godslayer armor box');
    expect(box.uses.single, contains('Godslayer armor part'));
  });

  test('Edania material descriptions do not repeat their Used For lines', () {
    final twilight = purposeFor('Twilight of the End - Earring');
    expect(twilight.description, 'A slot-specific Edania accessory material.');
    expect(twilight.uses, <String>[
      'Crafts the Earring versions of Causality Shardstone and Apeiron.',
    ]);

    final olivine = purposeFor('Magical Olivine Powder');
    expect(olivine.description, 'A refined Edania alchemy material.');
    expect(olivine.uses, <String>[
      'Crafts Perfume of Verdure and Viridian Draught.',
    ]);

    final dawn = purposeFor('Dawn Black Stone');
    expect(dawn.description, 'A high-tier Kharazad enhancement stone.');
    expect(dawn.uses, <String>['Enhances DEC (X) Kharazad accessories.']);
  });
}
