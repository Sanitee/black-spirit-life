final class ExactCrystalInfo {
  const ExactCrystalInfo({
    required this.title,
    this.kind,
    this.effectsTitle = 'Effects',
    this.effects = const <String>[],
    this.uses = const <String>[],
  });

  final String title;
  final String? kind;
  final String effectsTitle;
  final List<String> effects;
  final List<String> uses;
}

const List<String> _standardLightstoneUses = <String>[
  'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
  'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
];

final Map<String, ExactCrystalInfo>
exactCrystalInfoByName = <String, ExactCrystalInfo>{
  'ancient magic crystal - addis': ExactCrystalInfo(
    title: 'Ancient Magic Crystal - Addis',
    effects: <String>['Critical Hit +1', 'Casting Speed +1'],
  ),
  'ancient magic crystal - carmae': ExactCrystalInfo(
    title: 'Ancient Magic Crystal - Carmae',
    effects: <String>['Critical Hit +1', 'Attack Speed +1'],
  ),
  'ancient magic crystal - cobelinus': ExactCrystalInfo(
    title: 'Ancient Magic Crystal - Cobelinus',
    effects: <String>['Max HP +100', 'Weight Limit +20 LT'],
  ),
  'ancient magic crystal - harphia': ExactCrystalInfo(
    title: 'Ancient Magic Crystal - Harphia',
    effects: <String>['Max HP +50', 'HP Recovery +5'],
  ),
  'ancient magic crystal - hystria': ExactCrystalInfo(
    title: 'Ancient Magic Crystal - Hystria',
    effects: <String>['Weight Limit +20 LT', 'Movement Speed +1'],
  ),
  'ancient magic crystal - viper': ExactCrystalInfo(
    title: 'Ancient Magic Crystal - Viper',
    effects: <String>['Attack Speed +1', 'Casting Speed +1'],
  ),
  'ancient magic crystal of crimson flame - power': ExactCrystalInfo(
    title: 'Ancient Magic Crystal of Crimson Flame - Power',
    effects: <String>['All AP +5'],
  ),
  'ancient magic crystal of nature - adamantine': ExactCrystalInfo(
    title: 'Ancient Magic Crystal of Nature - Adamantine',
    effects: <String>['Knockdown/Bound Resistance +25%'],
  ),
  'ancient magic crystal of nature - fighting spirit': ExactCrystalInfo(
    title: 'Ancient Magic Crystal of Nature - Fighting Spirit',
    effects: <String>['Knockback/Floating Resistance +25%'],
  ),
  'ancient magic crystal of nature - giant': ExactCrystalInfo(
    title: 'Ancient Magic Crystal of Nature - Giant',
    effects: <String>['Stun/Stiffness/Freezing Resistance +25%'],
  ),
  'black magic crystal - adamantine': ExactCrystalInfo(
    title: 'Black Magic Crystal - Adamantine',
    effects: <String>[
      'Knockback/Floating Resistance +10%',
      'Knockdown/Bound Resistance +5%',
    ],
  ),
  'black magic crystal - addis': ExactCrystalInfo(
    title: 'Black Magic Crystal - Addis',
    effects: <String>['Critical Hit +1', 'Casting Speed +1', 'All AP +2'],
  ),
  'black magic crystal - agility': ExactCrystalInfo(
    title: 'Black Magic Crystal - Agility',
    effects: <String>['All Evasion +8', 'Knockdown/Bound Resistance +5%'],
  ),
  'black magic crystal - armor': ExactCrystalInfo(
    title: 'Black Magic Crystal - Armor',
    effects: <String>[
      'Monster Damage Reduction +3',
      'Stun/Stiffness/Freezing Resistance +10%',
    ],
  ),
  'black magic crystal - ascension': ExactCrystalInfo(
    title: 'Black Magic Crystal - Ascension',
    effects: <String>['Jump Height +35', 'Knockback/Floating Resistance +10%'],
  ),
  'black magic crystal - assault': ExactCrystalInfo(
    title: 'Black Magic Crystal - Assault',
    effects: <String>['Attack Speed +2', 'Knockdown/Bound Resistance +5%'],
  ),
  'black magic crystal - carmae': ExactCrystalInfo(
    title: 'Black Magic Crystal - Carmae',
    effects: <String>['Critical Hit +1', 'Attack Speed +1', 'All AP +2'],
  ),
  'black magic crystal - cobelinus': ExactCrystalInfo(
    title: 'Black Magic Crystal - Cobelinus',
    effects: <String>[
      'Max HP +100',
      'Weight Limit +20 LT',
      'All Damage Reduction +2',
    ],
  ),
  'black magic crystal - descent': ExactCrystalInfo(
    title: 'Black Magic Crystal - Descent',
    effects: <String>['Fall Damage -15%', 'Knockback/Floating Resistance +10%'],
  ),
  'black magic crystal - endurance': ExactCrystalInfo(
    title: 'Black Magic Crystal - Endurance',
    effects: <String>['Max Stamina +150', 'Knockback/Floating Resistance +10%'],
  ),
  'black magic crystal - ensnare': ExactCrystalInfo(
    title: 'Black Magic Crystal - Ensnare',
    effects: <String>['All Accuracy +8', 'Knockdown/Bound Resistance +5%'],
  ),
  'black magic crystal - harphia': ExactCrystalInfo(
    title: 'Black Magic Crystal - Harphia',
    effects: <String>['Max HP +50', 'HP Recovery +5', 'All Evasion +8'],
  ),
  'black magic crystal - healing': ExactCrystalInfo(
    title: 'Black Magic Crystal - Healing',
    effects: <String>[
      'HP Recovery +5',
      'Stun/Stiffness/Freezing Resistance +10%',
    ],
  ),
  'black magic crystal - hystria': ExactCrystalInfo(
    title: 'Black Magic Crystal - Hystria',
    effects: <String>[
      'Weight Limit +20 LT',
      'Movement Speed +1',
      'Max Stamina +275',
    ],
  ),
  'black magic crystal - intimidation': ExactCrystalInfo(
    title: 'Black Magic Crystal - Intimidation',
    effects: <String>[
      'Knockdown/Bound Resistance +10%',
      'Stun/Stiffness/Freezing Resistance +5%',
    ],
  ),
  'black magic crystal - memory': ExactCrystalInfo(
    title: 'Black Magic Crystal - Memory',
    effects: <String>['Casting Speed +2', 'Knockdown/Bound Resistance +5%'],
  ),
  'black magic crystal - patience': ExactCrystalInfo(
    title: 'Black Magic Crystal - Patience',
    effects: <String>[
      'Max MP/WP/SP +50',
      'Stun/Stiffness/Freezing Resistance +10%',
    ],
  ),
  'black magic crystal - power': ExactCrystalInfo(
    title: 'Black Magic Crystal - Power',
    effects: <String>['All AP +3'],
  ),
  'black magic crystal - precision': ExactCrystalInfo(
    title: 'Black Magic Crystal - Precision',
    effects: <String>['All Accuracy +12'],
  ),
  'black magic crystal - resonance': ExactCrystalInfo(
    title: 'Black Magic Crystal - Resonance',
    effects: <String>[
      'MP/WP/SP Recovery +5',
      'Stun/Stiffness/Freezing Resistance +10%',
    ],
  ),
  'black magic crystal - sturdiness': ExactCrystalInfo(
    title: 'Black Magic Crystal - Sturdiness',
    effects: <String>[
      'Knockdown/Bound Resistance +10%',
      'Knockback/Floating Resistance +5%',
    ],
  ),
  'black magic crystal - swiftness': ExactCrystalInfo(
    title: 'Black Magic Crystal - Swiftness',
    effects: <String>['Movement Speed +2', 'Knockback/Floating Resistance +5%'],
  ),
  'black magic crystal - valor': ExactCrystalInfo(
    title: 'Black Magic Crystal - Valor',
    effects: <String>['Critical Hit +2', 'Knockdown/Bound Resistance +5%'],
  ),
  'black magic crystal - vigor': ExactCrystalInfo(
    title: 'Black Magic Crystal - Vigor',
    effects: <String>['Max HP +50', 'Stun/Stiffness/Freezing Resistance +10%'],
  ),
  'black magic crystal - viper': ExactCrystalInfo(
    title: 'Black Magic Crystal - Viper',
    effects: <String>['Attack Speed +1', 'Casting Speed +1', 'All Accuracy +8'],
  ),
  'black spirit crystal': ExactCrystalInfo(
    title: 'Black Spirit Crystal',
    effects: <String>['Max HP +100', 'All AP +5'],
  ),
  'bon magic crystal - addis': ExactCrystalInfo(
    title: 'BON Magic Crystal - Addis',
    effects: <String>['Critical Hit +2', 'Casting Speed +1', 'All AP +3'],
  ),
  'bon magic crystal - carmae': ExactCrystalInfo(
    title: 'BON Magic Crystal - Carmae',
    effects: <String>['Critical Hit +2', 'Attack Speed +1', 'All AP +3'],
  ),
  'bon magic crystal - cobelinus': ExactCrystalInfo(
    title: 'BON Magic Crystal - Cobelinus',
    effects: <String>[
      'Max HP +150',
      'Weight Limit +20 LT',
      'All Damage Reduction +3',
    ],
  ),
  'bon magic crystal - harphia': ExactCrystalInfo(
    title: 'BON Magic Crystal - Harphia',
    effects: <String>['Max HP +75', 'HP Recovery +5', 'All Evasion +12'],
  ),
  'bon magic crystal - hystria': ExactCrystalInfo(
    title: 'BON Magic Crystal - Hystria',
    effects: <String>[
      'Weight Limit +50 LT',
      'Movement Speed +1',
      'Max Stamina +275',
    ],
  ),
  'bon magic crystal - viper': ExactCrystalInfo(
    title: 'BON Magic Crystal - Viper',
    effects: <String>[
      'Attack Speed +2',
      'Casting Speed +1',
      'All Accuracy +12',
    ],
  ),
  'combined magic crystal - gervish': ExactCrystalInfo(
    title: 'Combined Magic Crystal - Gervish',
    effects: <String>[
      '2-crystal set: Critical Hit +1, Movement Speed +1, Weight Limit +75 LT',
      '4-crystal set: Critical Hit +1, Movement Speed +1, Weight Limit +75 LT, Combat EXP +5%, Skill EXP +3%',
      'At 4 crystals, both set bonuses apply.',
    ],
  ),
  'combined magic crystal - hoom': ExactCrystalInfo(
    title: 'Combined Magic Crystal - Hoom',
    effects: <String>[
      '2-crystal set: All Damage Reduction +5, Max HP +150, All Evasion +4',
      '4-crystal set: All Damage Reduction +5, Max HP +150, All Evasion +4, All Accuracy +8, All Resistance +3%',
      'At 4 crystals, both set bonuses apply.',
    ],
  ),
  'combined magic crystal - macalod': ExactCrystalInfo(
    title: 'Combined Magic Crystal - Macalod',
    effects: <String>[
      '2-crystal set: All AP +5, Max Stamina +100, All Accuracy +4',
      '4-crystal set: All AP +5, Max Stamina +100, All Accuracy +4, Combat EXP +5%',
      'At 4 crystals, both set bonuses apply.',
    ],
  ),
  'crystal of precise destruction': ExactCrystalInfo(
    title: 'Crystal of Precise Destruction',
    effects: <String>[
      'Extra AP Against Monsters +6',
      'All Accuracy +3',
      'Critical Hit +3',
    ],
  ),
  'jin magic crystal - addis': ExactCrystalInfo(
    title: 'JIN Magic Crystal - Addis',
    effects: <String>['Critical Hit +1', 'Casting Speed +1', 'All AP +5'],
  ),
  'jin magic crystal - carmae': ExactCrystalInfo(
    title: 'JIN Magic Crystal - Carmae',
    effects: <String>['Critical Hit +1', 'Attack Speed +1', 'All AP +5'],
  ),
  'jin magic crystal - cobelinus': ExactCrystalInfo(
    title: 'JIN Magic Crystal - Cobelinus',
    effects: <String>[
      'Max HP +100',
      'Weight Limit +20 LT',
      'All Damage Reduction +5',
    ],
  ),
  'jin magic crystal - harphia': ExactCrystalInfo(
    title: 'JIN Magic Crystal - Harphia',
    effects: <String>['Max HP +50', 'HP Recovery +5', 'All Evasion +20'],
  ),
  'jin magic crystal - hystria': ExactCrystalInfo(
    title: 'JIN Magic Crystal - Hystria',
    effects: <String>[
      'Weight Limit +30 LT',
      'Movement Speed +1',
      'Max Stamina +300',
    ],
  ),
  'jin magic crystal - viper': ExactCrystalInfo(
    title: 'JIN Magic Crystal - Viper',
    effects: <String>[
      'Attack Speed +1',
      'Casting Speed +1',
      'All Accuracy +20',
    ],
  ),
  'magic crystal of infinity - armor': ExactCrystalInfo(
    title: 'Magic Crystal of Infinity - Armor',
    effects: <String>['All Damage Reduction +2'],
  ),
  'magic crystal of infinity - back attack': ExactCrystalInfo(
    title: 'Magic Crystal of Infinity - Back Attack',
    effects: <String>['Back Attack Extra Damage +10%'],
  ),
  'magic crystal of infinity - critical hit': ExactCrystalInfo(
    title: 'Magic Crystal of Infinity - Critical Hit',
    effects: <String>['Critical Hit Extra Damage +10%'],
  ),
  'magic crystal of infinity - experience': ExactCrystalInfo(
    title: 'Magic Crystal of Infinity - Experience',
    effects: <String>['Combat EXP +10%'],
  ),
  'magic crystal of infinity - skill': ExactCrystalInfo(
    title: 'Magic Crystal of Infinity - Skill',
    effects: <String>['Skill EXP +10%'],
  ),
  'valtarra spirit\'s crystal': ExactCrystalInfo(
    title: 'Valtarra Spirit\'s Crystal',
    effects: <String>[
      'Max HP +150',
      'All AP +5',
      'Extra AP Against Kamasylvian Monsters +3',
    ],
  ),
  'lightstone of earth: boulder': ExactCrystalInfo(
    title: 'Lightstone of Earth: Boulder',
    effects: <String>['Knockdown/Bound Resistance +2%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of earth: fitted': ExactCrystalInfo(
    title: 'Lightstone of Earth: Fitted',
    effects: <String>['Monster Damage Reduction +5'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of earth: iron wall': ExactCrystalInfo(
    title: 'Lightstone of Earth: Iron Wall',
    effects: <String>['All Damage Reduction +3'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of earth: mountain': ExactCrystalInfo(
    title: 'Lightstone of Earth: Mountain',
    effects: <String>['All Resistance +1%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of earth: roots': ExactCrystalInfo(
    title: 'Lightstone of Earth: Roots',
    effects: <String>['Knockback/Floating Resistance +2%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of earth: swamp': ExactCrystalInfo(
    title: 'Lightstone of Earth: Swamp',
    effects: <String>['Stun/Stiffness/Freezing Resistance +2%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of earth: veil': ExactCrystalInfo(
    title: 'Lightstone of Earth: Veil',
    effects: <String>['Monster Damage Reduction Rate +1%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of earth: waves': ExactCrystalInfo(
    title: 'Lightstone of Earth: Waves',
    effects: <String>['All Evasion +6'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: aerial': ExactCrystalInfo(
    title: 'Lightstone of Fire: Aerial',
    effects: <String>['Air Attack Extra Damage +1%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: blade': ExactCrystalInfo(
    title: 'Lightstone of Fire: Blade',
    effects: <String>['Critical Hit Rate +2%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: blight': ExactCrystalInfo(
    title: 'Lightstone of Fire: Blight',
    effects: <String>[
      'Extra AP Against Adventurers +4, Extra AP Against Humans +4',
    ],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: claws': ExactCrystalInfo(
    title: 'Lightstone of Fire: Claws',
    effects: <String>['Critical Hit +1'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: fallen': ExactCrystalInfo(
    title: 'Lightstone of Fire: Fallen',
    effects: <String>['Extra AP Against Kamasylvian Monsters +5'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: frenzy': ExactCrystalInfo(
    title: 'Lightstone of Fire: Frenzy',
    effects: <String>['All Special Attack Extra Damage +0.5%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: ground': ExactCrystalInfo(
    title: 'Lightstone of Fire: Ground',
    effects: <String>['Down Attack Extra Damage +1%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: marked': ExactCrystalInfo(
    title: 'Lightstone of Fire: Marked',
    effects: <String>['All Accuracy +4'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: predation': ExactCrystalInfo(
    title: 'Lightstone of Fire: Predation',
    effects: <String>['Extra AP Against Monsters +3'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: rage': ExactCrystalInfo(
    title: 'Lightstone of Fire: Rage',
    effects: <String>['All AP +2'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: roar': ExactCrystalInfo(
    title: 'Lightstone of Fire: Roar',
    effects: <String>['Extra AP Against Demihumans +5'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: rush': ExactCrystalInfo(
    title: 'Lightstone of Fire: Rush',
    effects: <String>['Movement Speed +1'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: shadows': ExactCrystalInfo(
    title: 'Lightstone of Fire: Shadows',
    effects: <String>['Back Attack Extra Damage +1%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: strike': ExactCrystalInfo(
    title: 'Lightstone of Fire: Strike',
    effects: <String>['Critical Hit Extra Damage +1%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: twisted': ExactCrystalInfo(
    title: 'Lightstone of Fire: Twisted',
    effects: <String>['Extra AP Against Edanian Monsters +5'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of fire: zeal': ExactCrystalInfo(
    title: 'Lightstone of Fire: Zeal',
    effects: <String>['Attack/Casting Speed +1'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of wind: alert (combat)': ExactCrystalInfo(
    title: 'Lightstone of Wind: Alert (Combat)',
    effects: <String>['Combat EXP +25%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of wind: alert (skill)': ExactCrystalInfo(
    title: 'Lightstone of Wind: Alert (Skill)',
    effects: <String>['Skill EXP +5%'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of wind: feather': ExactCrystalInfo(
    title: 'Lightstone of Wind: Feather',
    effects: <String>['Weight Limit +20 LT'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of wind: fortune': ExactCrystalInfo(
    title: 'Lightstone of Wind: Fortune',
    effects: <String>['Luck +1'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of wind: heart': ExactCrystalInfo(
    title: 'Lightstone of Wind: Heart',
    effects: <String>['Max HP +50'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of wind: lungs': ExactCrystalInfo(
    title: 'Lightstone of Wind: Lungs',
    effects: <String>['Max Stamina +25'],
    uses: _standardLightstoneUses,
  ),
  'lightstone of wind: mind': ExactCrystalInfo(
    title: 'Lightstone of Wind: Mind',
    effects: <String>['Max MP/WP/SP +50'],
    uses: _standardLightstoneUses,
  ),
  'ah\'krad crystal': ExactCrystalInfo(
    title: 'Ah\'krad Crystal',
    effects: <String>['All Accuracy +3', 'Extra AP Against Monsters +5'],
    uses: <String>[],
  ),
  'amplified lightstone of earth: boulder': ExactCrystalInfo(
    title: 'Amplified Lightstone of Earth: Boulder',
    effects: <String>['Knockdown/Bound Resistance +4%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of earth: fitted': ExactCrystalInfo(
    title: 'Amplified Lightstone of Earth: Fitted',
    effects: <String>['Monster Damage Reduction +7'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of earth: iron wall': ExactCrystalInfo(
    title: 'Amplified Lightstone of Earth: Iron Wall',
    effects: <String>['All Damage Reduction +5'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of earth: mountain': ExactCrystalInfo(
    title: 'Amplified Lightstone of Earth: Mountain',
    effects: <String>['All Resistance +2%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of earth: roots': ExactCrystalInfo(
    title: 'Amplified Lightstone of Earth: Roots',
    effects: <String>['Knockback/Floating Resistance +4%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of earth: swamp': ExactCrystalInfo(
    title: 'Amplified Lightstone of Earth: Swamp',
    effects: <String>['Stun/Stiffness/Freezing Resistance +4%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of earth: veil': ExactCrystalInfo(
    title: 'Amplified Lightstone of Earth: Veil',
    effects: <String>['Monster Damage Reduction Rate +1.5%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of earth: waves': ExactCrystalInfo(
    title: 'Amplified Lightstone of Earth: Waves',
    effects: <String>['All Evasion +10'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: aerial': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Aerial',
    effects: <String>['Air Attack Extra Damage +1.5%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: blade': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Blade',
    effects: <String>['Critical Hit Rate +3%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: blight': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Blight',
    effects: <String>[
      'Extra AP Against Adventurers +6',
      'Extra AP Against Humans +6',
    ],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: claws': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Claws',
    effects: <String>['Critical Hit +2'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: fallen': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Fallen',
    effects: <String>['Extra AP Against Kamasylvian Monsters +7'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: frenzy': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Frenzy',
    effects: <String>['All Special Attack Extra Damage +1%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: ground': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Ground',
    effects: <String>['Down Attack Extra Damage +1.5%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: marked': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Marked',
    effects: <String>['All Accuracy +8'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: predation': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Predation',
    effects: <String>['Extra AP Against Monsters +5'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: rage': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Rage',
    effects: <String>['All AP +4'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: roar': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Roar',
    effects: <String>['Extra AP Against Demihumans +7'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: rush': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Rush',
    effects: <String>['Movement Speed +2'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: shadows': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Shadows',
    effects: <String>['Back Attack Extra Damage +1.5%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: strike': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Strike',
    effects: <String>['Critical Hit Extra Damage +1.5%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: twisted': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Twisted',
    effects: <String>['Extra AP Against Edanian Monsters +7'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of fire: zeal': ExactCrystalInfo(
    title: 'Amplified Lightstone of Fire: Zeal',
    effects: <String>['Attack/Casting Speed +2'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of wind: alert (combat)': ExactCrystalInfo(
    title: 'Amplified Lightstone of Wind: Alert (Combat)',
    effects: <String>['Combat EXP +50%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of wind: alert (skill)': ExactCrystalInfo(
    title: 'Amplified Lightstone of Wind: Alert (Skill)',
    effects: <String>['Skill EXP +25%'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of wind: feather': ExactCrystalInfo(
    title: 'Amplified Lightstone of Wind: Feather',
    effects: <String>['Weight Limit +30 LT'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of wind: fortune': ExactCrystalInfo(
    title: 'Amplified Lightstone of Wind: Fortune',
    effects: <String>['Luck +2'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of wind: heart': ExactCrystalInfo(
    title: 'Amplified Lightstone of Wind: Heart',
    effects: <String>['Max HP +100'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of wind: lungs': ExactCrystalInfo(
    title: 'Amplified Lightstone of Wind: Lungs',
    effects: <String>['Max Stamina +50'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'amplified lightstone of wind: mind': ExactCrystalInfo(
    title: 'Amplified Lightstone of Wind: Mind',
    effects: <String>['Max MP/WP/SP +100'],
    uses: <String>[
      'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
      'Hand over Lightstone to Dalishain located in major cities and towns to receive Magical Lightstone Crystal.',
    ],
  ),
  'awakened spirit\'s crystal': ExactCrystalInfo(
    title: 'Awakened Spirit\'s Crystal',
    effects: <String>['Max HP +150', 'All AP +5'],
    uses: <String>[],
  ),
  'bon crystal of dusky ruin': ExactCrystalInfo(
    title: 'BON Crystal of Dusky Ruin',
    effects: <String>[
      'Extra AP Against Edanian Monsters +30',
      'Monster Damage Reduction +10',
    ],
    uses: <String>[],
  ),
  'bon wandering origin crystal': ExactCrystalInfo(
    title: 'BON Wandering Origin Crystal',
    kind: 'Gear crystal',
    effects: <String>[
      'Extra AP Against Edanian Monsters +120',
      'Monster Damage Reduction +20',
    ],
    uses: <String>[
      'Crystal group: Edania; maximum 1 equipped.',
      'Cannot be registered on the Central Market; NPC sell price: 1,500,000,000 Silver.',
    ],
  ),
  'bon dawn crystal - life exp': ExactCrystalInfo(
    title: 'BON Dawn Crystal - Life EXP',
    effects: <String>['Life EXP +8%'],
    uses: <String>[],
  ),
  'bonghwang\'s crystal': ExactCrystalInfo(
    title: 'Bonghwang\'s Crystal',
    effects: <String>[
      'All AP +4',
      'All Accuracy +5',
      'All Damage Reduction +5',
      'All Evasion +7',
      'Max HP +75',
      'Max MP/WP/SP +50',
      'Max Stamina +50',
      'Extra AP Against Monsters +2',
      'Monster Damage Reduction +2',
    ],
    uses: <String>[],
  ),
  'bonghwang\'s tear': ExactCrystalInfo(
    title: 'Bonghwang\'s Tear',
    effects: <String>[
      'All AP +4',
      'All Accuracy +5',
      'All Damage Reduction +5',
      'All Evasion +7',
      'Max HP +115',
      'Max MP/WP/SP +50',
      'Max Stamina +50',
      'Extra AP Against Monsters +2',
      'Monster Damage Reduction +2',
      'All Special Attack Extra Damage +0.5%',
      'All Resistance +2%',
      'Ignore All Resistance +2%',
      'Combat/Skill EXP +30%',
      'Item Drop Rate +5%',
    ],
    uses: <String>[],
  ),
  'coral crystal': ExactCrystalInfo(
    title: 'Coral Crystal',
    effects: <String>[],
    uses: <String>[],
  ),
  'corrupted gluttony crystal': ExactCrystalInfo(
    title: 'Corrupted Gluttony Crystal',
    effects: <String>[
      'Critical Hit Extra Damage +10%',
      'All AP +5',
      'All Damage Reduction -2',
      '2-crystal set: Critical Hit Extra Damage +2%',
    ],
    uses: <String>[],
  ),
  'corrupted magic crystal': ExactCrystalInfo(
    title: 'Corrupted Magic Crystal',
    effects: <String>[
      'Critical Hit Extra Damage +10%',
      'All AP +2',
      'All Damage Reduction -2',
      '2-crystal set: Critical Hit Extra Damage +2%',
    ],
    uses: <String>[],
  ),
  'crystal of breathing verdure': ExactCrystalInfo(
    title: 'Crystal of Breathing Verdure',
    effects: <String>['Life EXP +7%', 'Life Skill Mastery +15'],
    uses: <String>[],
  ),
  'crystal of brutal decimation': ExactCrystalInfo(
    title: 'Crystal of Brutal Decimation',
    effects: <String>[
      'Extra AP Against Monsters +7',
      'Back Attack Extra Damage +1%',
    ],
    uses: <String>[],
  ),
  'crystal of elkarr': ExactCrystalInfo(
    title: 'Crystal of Elkarr',
    effects: <String>['All Accuracy +18'],
    uses: <String>[],
  ),
  'crystal of frozen bitterness': ExactCrystalInfo(
    title: 'Crystal of Frozen Bitterness',
    effects: <String>[
      'All Damage Reduction +10',
      'All Evasion +12',
      'Monster Damage Reduction +3',
    ],
    uses: <String>[],
  ),
  'crystal of mysterious darkness': ExactCrystalInfo(
    title: 'Crystal of Mysterious Darkness',
    effects: <String>[
      'All AP +2',
      'All Accuracy +3',
      'Back Attack Extra Damage +12%',
    ],
    uses: <String>[],
  ),
  'crystal of void - ah\'krad': ExactCrystalInfo(
    title: 'Crystal of Void - Ah\'krad',
    effects: <String>[
      'All Accuracy +3',
      'Extra AP Against Monsters +9',
      'Attack/Casting Speed +1%',
    ],
    uses: <String>[],
  ),
  'crystal of void destruction': ExactCrystalInfo(
    title: 'Crystal of Void Destruction',
    effects: <String>[
      'Extra AP Against Monsters +8',
      'All Accuracy +3',
      'Critical Hit +3',
    ],
    uses: <String>[],
  ),
  'crystallized energy of endtimes': ExactCrystalInfo(
    title: 'Crystallized Energy of Endtimes',
    effects: <String>[],
    uses: <String>['Used to craft HAN Dawn Crystals.'],
  ),
  'dark red fang crystal - armor': ExactCrystalInfo(
    title: 'Dark Red Fang Crystal - Armor',
    effects: <String>['All Damage Reduction +7', 'All Resistance +2%'],
    uses: <String>[],
  ),
  'dark red fang crystal - valor': ExactCrystalInfo(
    title: 'Dark Red Fang Crystal - Valor',
    effects: <String>['Critical Hit +2', 'All AP +5'],
    uses: <String>[],
  ),
  'distorted crystal of origin': ExactCrystalInfo(
    title: 'Distorted Crystal of Origin',
    effects: <String>[],
    uses: <String>[
      'Prevents an enhancement-level drop when upgrading Distorted Slumbering Origin defense gear to Silent.',
      'Consumed on every attempt; failure adds no Enhancement Chance.',
    ],
  ),
  'flawless herald\'s crystal': ExactCrystalInfo(
    title: 'Flawless Herald\'s Crystal',
    effects: <String>[],
    uses: <String>[
      'Reforms Kabua\'s Artifact or a Dehkia\'s Artifact into its Heralding version.',
      'Kabua gains Extra AP Against Monsters +3, Monster Damage Reduction +5, and Max HP +250.',
      'Dehkia gains All AP +6 and Max HP +250.',
    ],
  ),
  'fused crystal of emotions': ExactCrystalInfo(
    title: 'Fused Crystal of Emotions',
    effects: <String>[],
    uses: <String>[
      'Crafts Refined Essence of Emotions, which removes a cup from a reformed accessory.',
    ],
  ),
  'fused crystal of decimation': ExactCrystalInfo(
    title: 'Fused Crystal of Decimation',
    kind: 'Gear crystal',
    effects: <String>[
      'Extra AP Against Monsters +10',
      'Back Attack Extra Damage +1.5%',
    ],
    uses: <String>['Crystal group: Decimation; maximum 2 equipped.'],
  ),
  'girin\'s crystal': ExactCrystalInfo(
    title: 'Girin\'s Crystal',
    effects: <String>[
      'All Accuracy +3',
      'Extra AP Against Monsters +10',
      'Monster Damage Reduction +10',
      'Max HP +75',
      'Max MP/WP/SP +50',
      'Max Stamina +50',
    ],
    uses: <String>[],
  ),
  'glorious crystal of gallantry - ah\'krad': ExactCrystalInfo(
    title: 'Glorious Crystal of Gallantry - Ah\'krad',
    effects: <String>[
      'All Accuracy +3',
      'Extra AP Against Monsters +7',
      'Attack/Casting Speed +1%',
    ],
    uses: <String>[],
  ),
  'glorious crystal of gallantry - olucas': ExactCrystalInfo(
    title: 'Glorious Crystal of Gallantry - Olucas',
    effects: <String>[
      'All Accuracy +3',
      'Extra AP Against Adventurers +7',
      'Extra AP Against Humans +7',
      'Attack/Casting Speed +1%',
    ],
    uses: <String>[],
  ),
  'han combined magic crystal - gervish': ExactCrystalInfo(
    title: 'HAN Combined Magic Crystal - Gervish',
    effects: <String>[
      'Combat/Skill EXP +1%',
      'Weight Limit +15 LT',
      '2-crystal set: Critical Hit +1, Movement Speed +1, Weight Limit +75 LT',
      '4-crystal set: Critical Hit +1, Movement Speed +1, Weight Limit +75 LT, Combat EXP +5%, Skill EXP +3%',
      'At 4 crystals, both set bonuses apply.',
    ],
    uses: <String>[],
  ),
  'han combined magic crystal - hoom': ExactCrystalInfo(
    title: 'HAN Combined Magic Crystal - Hoom',
    effects: <String>[
      'All Accuracy +2',
      'All Resistance +1%',
      'Max HP +30',
      '2-crystal set: All Damage Reduction +5, Max HP +150, All Evasion +4',
      '4-crystal set: All Damage Reduction +5, Max HP +150, All Evasion +4, All Accuracy +8, All Resistance +3%',
      'At 4 crystals, both set bonuses apply.',
    ],
    uses: <String>[],
  ),
  'han combined magic crystal - macalod': ExactCrystalInfo(
    title: 'HAN Combined Magic Crystal - Macalod',
    effects: <String>[
      'Combat EXP +1%',
      'Max Stamina +20',
      'Ignore All Resistance +1%',
      '2-crystal set: All AP +5, Max Stamina +100, All Accuracy +4',
      '4-crystal set: All AP +5, Max Stamina +100, All Accuracy +4, Combat EXP +5%, Ignore All Resistance +3%',
      'At 4 crystals, both set bonuses apply.',
    ],
    uses: <String>[],
  ),
  'han crystal of dusky ruin': ExactCrystalInfo(
    title: 'HAN Crystal of Dusky Ruin',
    effects: <String>[
      'Extra AP Against Edanian Monsters +60',
      'Monster Damage Reduction +20',
    ],
    uses: <String>[],
  ),
  'han wandering origin crystal': ExactCrystalInfo(
    title: 'HAN Wandering Origin Crystal',
    kind: 'Gear crystal',
    effects: <String>[
      'Extra AP Against Edanian Monsters +180',
      'Monster Damage Reduction +20',
    ],
    uses: <String>[
      'Crystal group: Edania; maximum 1 equipped.',
      'Cannot be registered on the Central Market; NPC sell price: 2,000,000,000 Silver.',
    ],
  ),
  'han dawn crystal - accuracy': ExactCrystalInfo(
    title: 'HAN Dawn Crystal - Accuracy',
    effects: <String>['All AP -10', 'All Accuracy +84', 'Max Stamina +50'],
    uses: <String>[
      'Heat to recover Essence of Dawn - Accuracy x450 and Crystallized Energy of Endtimes x100.',
    ],
  ),
  'han dawn crystal - all ap': ExactCrystalInfo(
    title: 'HAN Dawn Crystal - All AP',
    effects: <String>['All AP +7'],
    uses: <String>[
      'Heat to recover Essence of Dawn x30 and Crystallized Energy of Endtimes x100.',
    ],
  ),
  'han dawn crystal - black spirit\'s rage': ExactCrystalInfo(
    title: 'HAN Dawn Crystal - Black Spirit\'s Rage',
    effects: <String>['Black Spirit\'s Rage +25%'],
    uses: <String>[
      'Heat to recover Essence of Dawn - Black Spirit\'s Rage x350 and Crystallized Energy of Endtimes x100.',
    ],
  ),
  'han dawn crystal - damage reduction': ExactCrystalInfo(
    title: 'HAN Dawn Crystal - Damage Reduction',
    effects: <String>['All AP -60', 'All Damage Reduction +27', 'Max HP +300'],
    uses: <String>[
      'Heat to recover Essence of Dawn - Damage Reduction x250 and Crystallized Energy of Endtimes x100.',
    ],
  ),
  'han dawn crystal - evasion': ExactCrystalInfo(
    title: 'HAN Dawn Crystal - Evasion',
    effects: <String>['All AP -60', 'All Evasion +84', 'Max HP +300'],
    uses: <String>[
      'Heat to recover Essence of Dawn - Evasion x450 and Crystallized Energy of Endtimes x100.',
    ],
  ),
  'haetae\'s crystal': ExactCrystalInfo(
    title: 'Haetae\'s Crystal',
    effects: <String>[
      'All Damage Reduction +10',
      'All Evasion +15',
      'Max HP +200',
      'Max MP/WP/SP +50',
      'Max Stamina +50',
    ],
    uses: <String>[],
  ),
  'haetae\'s tear': ExactCrystalInfo(
    title: 'Haetae\'s Tear',
    effects: <String>[
      'All Damage Reduction +10',
      'All Evasion +15',
      'Max HP +350',
      'Max MP/WP/SP +50',
      'Max Stamina +50',
      'HP Recovery +25',
      'All Resistance +3%',
    ],
    uses: <String>[],
  ),
  'hard black crystal shard': ExactCrystalInfo(
    title: 'Hard Black Crystal Shard',
    effects: <String>[],
    uses: <String>[
      'Crafts concentrated enhancement materials for armor and selected reform materials.',
    ],
  ),
  'heartvein crystal': ExactCrystalInfo(
    title: 'Heartvein Crystal',
    effects: <String>[],
    uses: <String>['Craft Star of Nostos.'],
  ),
  'imperfect lightstone of earth': ExactCrystalInfo(
    title: 'Imperfect Lightstone of Earth',
    effects: <String>[],
    uses: <String>[
      'Purify through Guru 1+ Alchemy or exchange with Dalishain for a Purified Lightstone of Earth.',
    ],
  ),
  'imperfect lightstone of fire': ExactCrystalInfo(
    title: 'Imperfect Lightstone of Fire',
    effects: <String>[],
    uses: <String>[
      'Purify through Guru 1+ Alchemy or exchange with Dalishain for a Purified Lightstone of Fire.',
    ],
  ),
  'imperfect lightstone of flora': ExactCrystalInfo(
    title: 'Imperfect Lightstone of Flora',
    effects: <String>[],
    uses: <String>[
      'Purify through Guru 1+ Alchemy or exchange with Dalishain for a Purified Lightstone of Flora.',
    ],
  ),
  'imperfect lightstone of wind': ExactCrystalInfo(
    title: 'Imperfect Lightstone of Wind',
    effects: <String>[],
    uses: <String>[
      'Purify through Guru 1+ Alchemy or exchange with Dalishain for a Purified Lightstone of Wind.',
    ],
  ),
  'jin crystal of dusky ruin': ExactCrystalInfo(
    title: 'JIN Crystal of Dusky Ruin',
    effects: <String>[
      'Extra AP Against Edanian Monsters +45',
      'Monster Damage Reduction +15',
    ],
    uses: <String>[],
  ),
  'jin wandering origin crystal': ExactCrystalInfo(
    title: 'JIN Wandering Origin Crystal',
    kind: 'Gear crystal',
    effects: <String>[
      'Extra AP Against Edanian Monsters +150',
      'Monster Damage Reduction +20',
    ],
    uses: <String>[
      'Crystal group: Edania; maximum 1 equipped.',
      'Cannot be registered on the Central Market; NPC sell price: 1,700,000,000 Silver.',
    ],
  ),
  'jin dawn crystal - accuracy': ExactCrystalInfo(
    title: 'JIN Dawn Crystal - Accuracy',
    effects: <String>['All AP -14', 'All Accuracy +84', 'Max Stamina +50'],
    uses: <String>[],
  ),
  'jin dawn crystal - all ap': ExactCrystalInfo(
    title: 'JIN Dawn Crystal - All AP',
    effects: <String>['All AP +4'],
    uses: <String>[],
  ),
  'jin dawn crystal - black spirit\'s rage': ExactCrystalInfo(
    title: 'JIN Dawn Crystal - Black Spirit\'s Rage',
    effects: <String>['All AP -6', 'Black Spirit\'s Rage +25%'],
    uses: <String>[],
  ),
  'jin dawn crystal - damage reduction': ExactCrystalInfo(
    title: 'JIN Dawn Crystal - Damage Reduction',
    effects: <String>['All AP -60', 'All Damage Reduction +27', 'Max HP +150'],
    uses: <String>[],
  ),
  'jin dawn crystal - evasion': ExactCrystalInfo(
    title: 'JIN Dawn Crystal - Evasion',
    effects: <String>['All AP -60', 'All Evasion +84', 'Max HP +150'],
    uses: <String>[],
  ),
  'jin dawn crystal - life exp': ExactCrystalInfo(
    title: 'JIN Dawn Crystal - Life EXP',
    effects: <String>['Life EXP +15%'],
    uses: <String>[],
  ),
  'kydict\'s crystal - adventure': ExactCrystalInfo(
    title: 'Kydict\'s Crystal - Adventure',
    effects: <String>['Max HP +50', 'HP Recovery +5', 'Combat EXP +10%'],
    uses: <String>[],
  ),
  'kydict\'s crystal - giant': ExactCrystalInfo(
    title: 'Kydict\'s Crystal - Giant',
    effects: <String>[
      'Max HP +100',
      'All Damage Reduction +2',
      'Stun/Stiffness/Freezing Resistance +10%',
    ],
    uses: <String>[],
  ),
  'life crystal': ExactCrystalInfo(
    title: 'Life Crystal',
    effects: <String>['Life EXP +5%'],
    uses: <String>[],
  ),
  'eltro crystal': ExactCrystalInfo(
    title: 'Eltro Crystal',
    kind: 'Sea Crystal container',
    effectsTitle: 'Possible Sea Crystal Stats',
    effects: <String>[
      'Speed +0.6% to +1.0%',
      'Acceleration +0.6% to +1.0%',
      'Turn +1.2% to +2.0%',
      'Brake +1.2% to +2.0%',
      'Weight +180 LT to +300 LT',
      'Max Durability +3,000 to +5,000',
      'Extra Damage to Ships and Sea Monsters +312 to +520 per hit',
    ],
    uses: <String>[
      'Open it to receive an Eltro Sea Crystal with one randomly selected ship stat.',
    ],
  ),
  'eltro sea crystal': ExactCrystalInfo(
    title: 'Eltro Sea Crystal',
    kind: 'Ship crystal',
    uses: <String>[
      'Install it on an eligible large ship; the stat and value depend on that specific crystal.',
      'Can be processed into Origin of Eltro.',
    ],
  ),
  'margoria crystal': ExactCrystalInfo(
    title: 'Margoria Crystal',
    kind: 'Sea Crystal container',
    effectsTitle: 'Possible Sea Crystal Stats',
    effects: <String>[
      'Speed +3.6% to +4.0%',
      'Acceleration +3.6% to +4.0%',
      'Turn +7.2% to +8.0%',
      'Brake +7.2% to +8.0%',
      'Weight +1,080 LT to +1,200 LT',
      'Max Durability +18,000 to +20,000',
      'Extra Damage to Ships and Sea Monsters +1,872 to +2,080 per hit',
    ],
    uses: <String>[
      'Open it to receive a Margoria Sea Crystal with one randomly selected ship stat.',
    ],
  ),
  'margoria sea crystal': ExactCrystalInfo(
    title: 'Margoria Sea Crystal',
    kind: 'Ship crystal',
    uses: <String>[
      'Install it on an eligible large ship; the stat and value depend on that specific crystal.',
      'Can be processed into Origin of Margoria.',
    ],
  ),
  'mud crystal': ExactCrystalInfo(
    title: 'Mud Crystal',
    effects: <String>[],
    uses: <String>[
      'Crafts Black Gem Fragments, Splash Swimming Goggles, and selected workshop furnishings.',
    ],
  ),
  'olucas\' crystal': ExactCrystalInfo(
    title: 'Olucas\' Crystal',
    effects: <String>[
      'All Accuracy +3',
      'Extra AP Against Adventurers +5',
      'Extra AP Against Humans +5',
    ],
    uses: <String>[],
  ),
  'oquilla earth crystal': ExactCrystalInfo(
    title: 'Oquilla Earth Crystal',
    effects: <String>[],
    uses: <String>[
      'Completes Jetina\'s guaranteed PEN boss-armor reform path.',
    ],
  ),
  'oquilla sky crystal': ExactCrystalInfo(
    title: 'Oquilla Sky Crystal',
    effects: <String>[],
    uses: <String>[
      'Completes Jetina\'s guaranteed PEN boss-weapon reform path.',
    ],
  ),
  'primordial glow crystal': ExactCrystalInfo(
    title: 'Primordial Glow Crystal',
    effects: <String>[],
    uses: <String>[
      'Reforms Sunset Artina Sol into Primordial Artina Sol, adding Extra AP Against Monsters +10 and Primordial reforging.',
    ],
  ),
  'pure copper crystal': ExactCrystalInfo(
    title: 'Pure Copper Crystal',
    effects: <String>[],
    uses: <String>['Crafts equipment and selected workshop furnishings.'],
  ),
  'pure gold crystal': ExactCrystalInfo(
    title: 'Pure Gold Crystal',
    effects: <String>[],
    uses: <String>['Crafts accessories and selected workshop furnishings.'],
  ),
  'pure iron crystal': ExactCrystalInfo(
    title: 'Pure Iron Crystal',
    effects: <String>[],
    uses: <String>['Crafts equipment and selected workshop furnishings.'],
  ),
  'pure lead crystal': ExactCrystalInfo(
    title: 'Pure Lead Crystal',
    effects: <String>[],
    uses: <String>['Crafts equipment and selected workshop furnishings.'],
  ),
  'pure mythril crystal': ExactCrystalInfo(
    title: 'Pure Mythril Crystal',
    effects: <String>[],
    uses: <String>['Crafts Krogdalo\'s Horseshoes and Camping Anvils.'],
  ),
  'pure nickel crystal': ExactCrystalInfo(
    title: 'Pure Nickel Crystal',
    effects: <String>[],
    uses: <String>[
      'Crafts Musical Spirit Wall Lamps and selected furnishings.',
    ],
  ),
  'pure noc crystal': ExactCrystalInfo(
    title: 'Pure Noc Crystal',
    effects: <String>[],
    uses: <String>[
      'Crafts barding, Forest Path Wagon Badges, and selected furnishings.',
    ],
  ),
  'pure platinum crystal': ExactCrystalInfo(
    title: 'Pure Platinum Crystal',
    effects: <String>[],
    uses: <String>[
      'Crafts Black Gold Ingots, Old Moon Censers, and equipment.',
    ],
  ),
  'pure silver crystal': ExactCrystalInfo(
    title: 'Pure Silver Crystal',
    effects: <String>[],
    uses: <String>['Crafts equipment and outfits.'],
  ),
  'pure tin crystal': ExactCrystalInfo(
    title: 'Pure Tin Crystal',
    effects: <String>[],
    uses: <String>['Crafts Old Moon Censers and equipment.'],
  ),
  'pure titanium crystal': ExactCrystalInfo(
    title: 'Pure Titanium Crystal',
    effects: <String>[],
    uses: <String>['Crafts accessories, barding, and outfits.'],
  ),
  'pure vanadium crystal': ExactCrystalInfo(
    title: 'Pure Vanadium Crystal',
    effects: <String>[],
    uses: <String>['Crafts equipment, accessories, and barding.'],
  ),
  'pure zinc crystal': ExactCrystalInfo(
    title: 'Pure Zinc Crystal',
    effects: <String>[],
    uses: <String>['Crafts equipment.'],
  ),
  'purified lightstone': ExactCrystalInfo(
    title: 'Purified Lightstone',
    kind: 'Lightstone container',
    effects: <String>[],
    uses: <String>['Open it to obtain one random Lightstone.'],
  ),
  'purified lightstone of earth': ExactCrystalInfo(
    title: 'Purified Lightstone of Earth',
    kind: 'Lightstone container',
    effects: <String>[],
    uses: <String>['Open it to obtain one random Earth Lightstone.'],
  ),
  'purified lightstone of fire': ExactCrystalInfo(
    title: 'Purified Lightstone of Fire',
    kind: 'Lightstone container',
    effects: <String>[],
    uses: <String>['Open it to obtain one random Fire Lightstone.'],
  ),
  'purified lightstone of flora': ExactCrystalInfo(
    title: 'Purified Lightstone of Flora',
    kind: 'Lightstone container',
    effects: <String>[],
    uses: <String>['Open it to obtain one random Flora Lightstone.'],
  ),
  'purified lightstone of wind': ExactCrystalInfo(
    title: 'Purified Lightstone of Wind',
    kind: 'Lightstone container',
    effects: <String>[],
    uses: <String>['Open it to obtain one random Wind Lightstone.'],
  ),
  'rebellious spirit crystal': ExactCrystalInfo(
    title: 'Rebellious Spirit Crystal',
    effects: <String>[
      'Max HP +175',
      'All AP +5',
      'Extra AP Against Monsters +5',
      'Skill EXP +5%',
    ],
    uses: <String>[],
  ),
  'red battlefield crystal: addis': ExactCrystalInfo(
    title: 'Red Battlefield Crystal: Addis',
    effects: <String>[
      'Critical Hit +1',
      'Casting Speed +1',
      'Extra AP Against Adventurers +8',
      'Extra AP Against Humans +8',
    ],
    uses: <String>[],
  ),
  'red battlefield crystal: carmae': ExactCrystalInfo(
    title: 'Red Battlefield Crystal: Carmae',
    effects: <String>[
      'Critical Hit +1',
      'Attack Speed +1',
      'Extra AP Against Adventurers +8',
      'Extra AP Against Humans +8',
    ],
    uses: <String>[],
  ),
  'red battlefield crystal: cobelinus': ExactCrystalInfo(
    title: 'Red Battlefield Crystal: Cobelinus',
    effects: <String>[
      'Max HP +100',
      'Weight Limit +20 LT',
      'Extra AP Against Adventurers +5',
      'Extra AP Against Humans +5',
    ],
    uses: <String>[],
  ),
  'red battlefield crystal: harphia': ExactCrystalInfo(
    title: 'Red Battlefield Crystal: Harphia',
    effects: <String>[
      'Max HP +75',
      'HP Recovery +5',
      'Extra AP Against Adventurers +5',
      'Extra AP Against Humans +5',
    ],
    uses: <String>[],
  ),
  'red battlefield crystal: hystria': ExactCrystalInfo(
    title: 'Red Battlefield Crystal: Hystria',
    effects: <String>[
      'Weight Limit +20 LT',
      'Movement Speed +1',
      'Extra AP Against Adventurers +7',
      'Extra AP Against Humans +7',
    ],
    uses: <String>[],
  ),
  'red battlefield crystal: power': ExactCrystalInfo(
    title: 'Red Battlefield Crystal: Power',
    effects: <String>[
      'All AP +5',
      'Extra AP Against Adventurers +3',
      'Extra AP Against Humans +3',
    ],
    uses: <String>[],
  ),
  'red battlefield crystal: viper': ExactCrystalInfo(
    title: 'Red Battlefield Crystal: Viper',
    effects: <String>[
      'Attack Speed +1',
      'Casting Speed +1',
      'Extra AP Against Adventurers +10',
      'Extra AP Against Humans +10',
    ],
    uses: <String>[],
  ),
  'red spirit crystal': ExactCrystalInfo(
    title: 'Red Spirit Crystal',
    effects: <String>[
      'Max HP +100',
      'All AP +5',
      'Extra AP Against Adventurers +3',
      'Extra AP Against Humans +3',
    ],
    uses: <String>[],
  ),
  'rusalka crystal': ExactCrystalInfo(
    title: 'Rusalka Crystal',
    kind: 'Sea Crystal container',
    effectsTitle: 'Possible Sea Crystal Stats',
    effects: <String>[
      'Speed +4.5%',
      'Acceleration +4.5%',
      'Turn +9.0%',
      'Brake +9.0%',
      'Weight +1,350 LT',
      'Max Durability +22,500',
      'Extra Damage to Ships and Sea Monsters +2,340 per hit',
    ],
    uses: <String>[
      'Open it to receive a Rusalka Sea Crystal with one randomly selected ship stat.',
    ],
  ),
  'rusalka sea crystal': ExactCrystalInfo(
    title: 'Rusalka Sea Crystal',
    kind: 'Ship crystal',
    uses: <String>[
      'Install it on an eligible large ship; the stat and value depend on that specific crystal.',
      "Can be processed into Origin of Rusalka or Oceanteared Ebenruth's Nol.",
    ],
  ),
  'serni crystal': ExactCrystalInfo(
    title: 'Serni Crystal',
    kind: 'Sea Crystal container',
    effectsTitle: 'Possible Sea Crystal Stats',
    effects: <String>[
      'Speed +1.6% to +2.0%',
      'Acceleration +1.6% to +2.0%',
      'Turn +3.2% to +4.0%',
      'Brake +3.2% to +4.0%',
      'Weight +480 LT to +600 LT',
      'Max Durability +8,000 to +10,000',
      'Extra Damage to Ships and Sea Monsters +832 to +1,040 per hit',
    ],
    uses: <String>[
      'Open it to receive a Serni Sea Crystal with one randomly selected ship stat.',
    ],
  ),
  'serni sea crystal': ExactCrystalInfo(
    title: 'Serni Sea Crystal',
    kind: 'Ship crystal',
    uses: <String>[
      'Install it on an eligible large ship; the stat and value depend on that specific crystal.',
      'Can be processed into Origin of Serni.',
    ],
  ),
  'sharp black crystal shard': ExactCrystalInfo(
    title: 'Sharp Black Crystal Shard',
    effects: <String>[],
    uses: <String>[
      'Crafts concentrated and flawless enhancement stones plus selected reform materials.',
    ],
  ),
  'silent crystal of origin': ExactCrystalInfo(
    title: 'Silent Crystal of Origin',
    effects: <String>[],
    uses: <String>[
      'Prevents an enhancement-level drop when upgrading Silent Slumbering Origin defense gear to Wailing.',
      'Consumed on every attempt; failure adds no Enhancement Chance.',
    ],
  ),
  'sunset glow crystal': ExactCrystalInfo(
    title: 'Sunset Glow Crystal',
    effects: <String>[],
    uses: <String>[
      'Reforms Artina Sol into Sunset Artina Sol, adding Extra AP Against Monsters +35.',
      'Heat with 1 Forest Fury to recover 10,000 Caphras Stones.',
    ],
  ),
  'sycraia crystal - adamantine': ExactCrystalInfo(
    title: 'Sycraia Crystal - Adamantine',
    effects: <String>[
      'Extra AP Against Monsters +4',
      'Knockdown/Bound Resistance +25%',
    ],
    uses: <String>[],
  ),
  'sycraia crystal - fighting spirit': ExactCrystalInfo(
    title: 'Sycraia Crystal - Fighting Spirit',
    effects: <String>[
      'Extra AP Against Monsters +4',
      'Knockback/Floating Resistance +25%',
    ],
    uses: <String>[],
  ),
  'sycraia crystal - giant': ExactCrystalInfo(
    title: 'Sycraia Crystal - Giant',
    effects: <String>[
      'Extra AP Against Monsters +4',
      'Stun/Stiffness/Freezing Resistance +25%',
    ],
    uses: <String>[],
  ),
  'translucent crystal': ExactCrystalInfo(
    title: 'Translucent Crystal',
    effects: <String>[],
    uses: <String>['Crafts accessories, outfits, and selected furnishings.'],
  ),
  'ultimate combined magic crystal - gervish': ExactCrystalInfo(
    title: 'Ultimate Combined Magic Crystal - Gervish',
    effects: <String>[
      'Combat/Skill EXP +10%',
      'Weight Limit +25 LT',
      '2-crystal set: Critical Hit +1, Movement Speed +1, Weight Limit +75 LT',
      '4-crystal set: Critical Hit +1, Movement Speed +1, Weight Limit +75 LT, Combat EXP +5%, Skill EXP +3%',
      'At 4 crystals, both set bonuses apply.',
    ],
    uses: <String>[],
  ),
  'ultimate combined magic crystal - hoom': ExactCrystalInfo(
    title: 'Ultimate Combined Magic Crystal - Hoom',
    effects: <String>[
      'All Accuracy +2',
      'All Damage Reduction +3',
      'All Evasion +5',
      'Max HP +75',
      'All Resistance +1%',
      '2-crystal set: All Damage Reduction +5, Max HP +150, All Evasion +4',
      '4-crystal set: All Damage Reduction +5, Max HP +150, All Evasion +4, All Accuracy +8, All Resistance +3%',
      'At 4 crystals, both set bonuses apply.',
    ],
    uses: <String>[],
  ),
  'ultimate combined magic crystal - macalod': ExactCrystalInfo(
    title: 'Ultimate Combined Magic Crystal - Macalod',
    effects: <String>[
      'All AP +3',
      'Max Stamina +30',
      'Ignore All Resistance +2%',
      'Combat EXP +3%',
      '2-crystal set: All AP +5, Max Stamina +100, All Accuracy +4',
      '4-crystal set: All AP +5, Max Stamina +100, All Accuracy +4, Combat EXP +5%, Ignore All Resistance +3%',
      'At 4 crystals, both set bonuses apply.',
    ],
    uses: <String>[],
  ),
  'violet crystal': ExactCrystalInfo(
    title: 'Violet Crystal',
    effects: <String>[],
    uses: <String>['Used in selected workshop furnishing recipes.'],
  ),
  'visionary crystal of elkarr': ExactCrystalInfo(
    title: 'Visionary Crystal of Elkarr',
    effects: <String>['All Accuracy +30'],
    uses: <String>[],
  ),
  'vital crystal': ExactCrystalInfo(
    title: 'Vital Crystal',
    effects: <String>['Life Skill Mastery +10'],
    uses: <String>[],
  ),
  'won crystal of dusky ruin': ExactCrystalInfo(
    title: 'WON Crystal of Dusky Ruin',
    effects: <String>[
      'Extra AP Against Edanian Monsters +15',
      'Monster Damage Reduction +5',
    ],
    uses: <String>[],
  ),
  'won wandering origin crystal': ExactCrystalInfo(
    title: 'WON Wandering Origin Crystal',
    kind: 'Gear crystal',
    effects: <String>[
      'Extra AP Against Edanian Monsters +90',
      'Monster Damage Reduction +20',
    ],
    uses: <String>[
      'Crystal group: Edania; maximum 1 equipped.',
      'Cannot be registered on the Central Market; NPC sell price: 1,200,000,000 Silver.',
    ],
  ),
  'won dawn crystal - life exp': ExactCrystalInfo(
    title: 'WON Dawn Crystal - Life EXP',
    effects: <String>['Life EXP +4%'],
    uses: <String>[],
  ),
  'won magic crystal - addis': ExactCrystalInfo(
    title: 'WON Magic Crystal - Addis',
    effects: <String>['Critical Hit +1', 'Casting Speed +2', 'All AP +3'],
    uses: <String>[],
  ),
  'won magic crystal - carmae': ExactCrystalInfo(
    title: 'WON Magic Crystal - Carmae',
    effects: <String>['Critical Hit +1', 'Attack Speed +2', 'All AP +3'],
    uses: <String>[],
  ),
  'won magic crystal - cobelinus': ExactCrystalInfo(
    title: 'WON Magic Crystal - Cobelinus',
    effects: <String>[
      'Max HP +100',
      'Weight Limit +50 LT',
      'All Damage Reduction +3',
    ],
    uses: <String>[],
  ),
  'won magic crystal - harphia': ExactCrystalInfo(
    title: 'WON Magic Crystal - Harphia',
    effects: <String>['Max HP +50', 'HP Recovery +10', 'All Evasion +12'],
    uses: <String>[],
  ),
  'won magic crystal - hystria': ExactCrystalInfo(
    title: 'WON Magic Crystal - Hystria',
    effects: <String>[
      'Weight Limit +20 LT',
      'Movement Speed +2',
      'Max Stamina +275',
    ],
    uses: <String>[],
  ),
  'won magic crystal - viper': ExactCrystalInfo(
    title: 'WON Magic Crystal - Viper',
    effects: <String>[
      'Attack Speed +1',
      'Casting Speed +2',
      'All Accuracy +12',
    ],
    uses: <String>[],
  ),
};
