/// Short reference facts from reviewed PC item descriptions.
/// Shared recipe formulas and reverse crafting uses remain catalog-derived.
class ExchangeItemDetails {
  const ExchangeItemDetails(
    this.summary, {
    this.uses = const [],
    this.effects = const [],
    this.notes = const [],
    this.kind = 'Item',
    this.howToObtain = const [],
    this.recipes = const [],
  });
  final String summary;
  final List<String> uses;
  final List<String> effects;
  final List<String> notes;
  final String kind;
  final List<String> howToObtain;
  final List<ExchangeReferenceRecipe> recipes;
}

/// Display-only fallback for a verified use absent from the crafting catalog.
/// It never adds a Planner target or changes exchange/market calculations.
class ExchangeReferenceRecipe {
  const ExchangeReferenceRecipe(this.output, this.method, this.ingredients);
  final String output;
  final String method;
  final Map<String, double> ingredients;
}

const exchangeItemDetails = <int, ExchangeItemDetails>{
  // Reviewed 2026-10-17. Current in-game time reduction and repair text:
  // https://bdocodex.com/us/item/3743/?sl=1
  // https://bdocodex.com/gl/item/3744/
  // The official PC cooking/alchemy events confirm 5,000 durability:
  // https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=6118
  // https://store.steampowered.com/news/posts/?appids=582660&enddate=1718764668&feed=steam_community_announcements
  3743: ExchangeItemDetails(
    'Install in a residence or manor to cook.',
    kind: 'Cooking utensil',
    effects: ['Cooking Time −1 sec', 'Durability: 5,000'],
    notes: [
      "Restore durability with Baermalo Hona's Supreme Cooking Repair Tool.",
    ],
  ),
  3744: ExchangeItemDetails(
    'Install in a residence or manor to perform alchemy.',
    kind: 'Alchemy tool',
    effects: ['Alchemy Time −1 sec', 'Durability: 5,000'],
    notes: ["Restore durability with Lomerun's Supreme Alchemy Repair Tool."],
  ),
  // Current seven-day item and its unopened box (not the old durability item):
  // https://bdocodex.com/us/item/12930/
  // https://bdocodex.com/seaen/item/890101/
  12930: ExchangeItemDetails(
    'A temporary chair used while fishing.',
    kind: 'Fishing chair',
    notes: [
      'Expires 7 days after being obtained from its box.',
      'Cannot be repaired.',
    ],
  ),
  // Royal Workshop goods: official PC effects, duration and cooldown table:
  // https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=6551
  // Paired-item restrictions are from the current in-game item descriptions:
  // https://bdocodex.com/us/item/821137/
  821137: ExchangeItemDetails(
    'A Royal Workshop meal for combat training.',
    kind: 'Consumable',
    effects: ['Extra AP Against Monsters +3', 'Combat EXP +500%'],
    howToObtain: ['Produce at a Royal Workshop.'],
    notes: [
      'Duration: 3 hours.',
      'Cooldown: 3 hours.',
      'Cannot be used together with Bountiful Feast.',
    ],
  ),
  // https://bdocodex.com/us/item/821139/
  821139: ExchangeItemDetails(
    'A Royal Workshop snack for monster hunting.',
    kind: 'Consumable',
    effects: ['Extra AP Against Monsters +3', 'Item Drop Rate +50%'],
    howToObtain: ['Produce at a Royal Workshop.'],
    notes: [
      'Duration: 3 hours.',
      'Cooldown: 3 hours.',
      'Cannot be used together with Traditional Tea & Snacks.',
    ],
  ),
  // https://bdocodex.com/us/item/821141/
  821141: ExchangeItemDetails(
    'A Royal Workshop dish for life-skill training.',
    kind: 'Consumable',
    effects: ['Life EXP +150%', 'Weight Limit +50 LT'],
    howToObtain: ['Produce at a Royal Workshop.'],
    notes: [
      'Duration: 3 hours.',
      'Cooldown: 3 hours.',
      'Cannot be used together with Assorted Kimchi.',
    ],
  ),
  // https://bdocodex.com/us/item/821143/
  821143: ExchangeItemDetails(
    'A Royal Workshop dish that increases Life Skill Mastery.',
    kind: 'Consumable',
    effects: ['Life Skill Mastery +300', 'Weight Limit +50 LT'],
    howToObtain: ['Produce at a Royal Workshop.'],
    notes: [
      'Duration: 3 hours.',
      'Cooldown: 3 hours.',
      'Cannot be used together with Yeolgujatang.',
    ],
  ),
  // https://bdocodex.com/kr/item/821145/
  // The English names and effects also appear in the official table above.
  821145: ExchangeItemDetails(
    'A Royal Workshop medicine that increases Energy recovery.',
    kind: 'Consumable',
    effects: ['Energy Recovery +25', 'Weight Limit +50 LT'],
    howToObtain: ['Produce at a Royal Workshop.'],
    notes: [
      'Duration: 3 hours.',
      'Cooldown: 3 hours.',
      'Cannot be used together with Mystical Herbal Medicine.',
    ],
  ),
  // Reviewed 2026-10-17. In-game item text: bdocodex.com/us/item/<id>/.
  // Tool stats also confirmed in the official PC Morning Light update:
  // blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=3855.
  3749: ExchangeItemDetails(
    'Install in a residence or manor to cook.',
    kind: 'Cooking utensil',
    effects: ['Cooking Time −1 sec', 'Durability: 3,000'],
    howToObtain: [
      'Exchange 100 Sangpyeong Coins with Wolim, Maksoon or Ahryung in Land of the Morning Light.',
      'Craft at a Lv. 2 Tool Workshop in Land of the Morning Light, or buy from the Central Market.',
    ],
    notes: [
      'Restore durability with a Morning Light Traditional Cooking Repair Tool.',
    ],
  ),
  3750: ExchangeItemDetails(
    'Install in a residence or manor to perform alchemy.',
    kind: 'Alchemy tool',
    effects: ['Alchemy Time −1 sec', 'Durability: 3,000'],
    howToObtain: [
      'Exchange 100 Sangpyeong Coins with Deokpal in Dalbeol Village.',
      'Craft at a Lv. 2 Tool Workshop in Land of the Morning Light, or buy from the Central Market.',
    ],
    notes: [
      'Restore durability with a Morning Light Traditional Alchemy Repair Tool.',
    ],
  ),
  // Finished-food formula and effects: https://bdocodex.com/us/item/820146/
  820139: ExchangeItemDetails(
    'A special meat used to make Miraculous Nourishing Soup.',
    kind: 'Cooking ingredient',
    howToObtain: [
      'Exchange 500 Sangpyeong Coins with Wolim, Maksoon or Ahryung in Land of the Morning Light.',
      'Butcher sniper-hunted animals in Land of the Morning Light.',
    ],
    recipes: [
      ExchangeReferenceRecipe('Miraculous Nourishing Soup', 'Simple Cooking', {
        'Live Meat': 1,
        'Jujube': 5,
        'Youngji Mushroom': 5,
        'Tiger Meat': 5,
        'Mineral Water': 2,
      }),
    ],
    notes: [
      'The finished soup gives Max HP +200 and Max Stamina +100 for 30 min. Cooldown: 22 hours.',
      'The finished soup cannot be used together with Iridescent Maehwa Liquor.',
    ],
  ),
  // Finished-food formula and effects: https://bdocodex.com/us/item/820147/
  820140: ExchangeItemDetails(
    'A special rice used to make Miraculous Tteokguk.',
    kind: 'Cooking ingredient',
    howToObtain: [
      'Exchange 10 Sangpyeong Coins with Wolim, Maksoon or Ahryung in Land of the Morning Light.',
      'Grow its special seed in a garden.',
    ],
    recipes: [
      ExchangeReferenceRecipe('Miraculous Tteokguk', 'Simple Cooking', {
        'Strange and Beautiful Rice': 50,
        'Garaetteok': 1,
        'Pork': 1,
        'Egg': 1,
        'Mineral Water': 1,
      }),
    ],
    notes: [
      'The finished Tteokguk instantly restores 5,000 HP. Cooldown: 22 hours.',
    ],
  ),
  820141: ExchangeItemDetails(
    'A rare Maehwa flower used to make Iridescent Maehwa Liquor.',
    kind: 'Cooking ingredient',
  ),
  820143: ExchangeItemDetails(
    'A special herb used to make Miraculous Herbal Medicine.',
    kind: 'Alchemy ingredient',
  ),
  820893: ExchangeItemDetails(
    'A shipbuilding material for the Panokseon and its equipment.',
    kind: 'Ship material',
    howToObtain: ['Exchange 10 Sangpyeong Coins with Yooan in Moodle Village.'],
  ),
  // Current item text and official PC crystal table:
  // blackdesert.pearlabyss.com/TR/en-us/News/Notice/Detail?_boardNo=17970.
  15734: ExchangeItemDetails(
    'Equip in a crystal preset for combat bonuses.',
    kind: 'Crystal',
    effects: [
      'All Accuracy +3',
      'Extra AP Against Monsters +10',
      'Monster Damage Reduction +10',
    ],
    uses: ["Make Girin's Crystal through Simple Alchemy."],
  ),
  15729: ExchangeItemDetails(
    'Equip in a crystal preset for combat bonuses.',
    kind: 'Crystal',
    effects: [
      'All AP +4',
      'All Accuracy +5',
      'All Damage Reduction +5',
      'All Evasion +7',
    ],
    uses: ["Make Bonghwang's Crystal through Simple Alchemy."],
  ),
  15731: ExchangeItemDetails(
    'Equip in a crystal preset for combat bonuses.',
    kind: 'Crystal',
    effects: ['All Damage Reduction +10', 'All Evasion +15'],
    uses: ["Make Haetae's Crystal through Simple Alchemy."],
  ),
  820036: ExchangeItemDetails(
    'A crafting material for Life Crystals and Vital Crystals.',
    kind: 'Crystal material',
    uses: ['Craft through Simple Alchemy.'],
  ),
  820035: ExchangeItemDetails(
    'A material for Ultimate Combined Magic Crystals: Gervish, Macalod and Hoom.',
    kind: 'Crystal material',
    uses: ['Craft through Simple Alchemy.'],
  ),
  320009: ExchangeItemDetails(
    'Changes a main weapon to one for your current class.',
    notes: [
      'Enhancement and Caphras levels are kept.',
      'Cannot be used on Tuvala weapons.',
    ],
  ),
  320010: ExchangeItemDetails(
    'Changes a sub-weapon to one for your current class.',
    notes: [
      'Enhancement and Caphras levels are kept.',
      'Cannot be used on Tuvala weapons.',
    ],
  ),
  320011: ExchangeItemDetails(
    'Changes an awakening weapon to one for your current class.',
    notes: [
      'Enhancement and Caphras levels are kept.',
      'Cannot be used on Tuvala weapons.',
    ],
  ),
  890001: ExchangeItemDetails(
    'Contains a random amount of gold bars.',
    uses: ['Open for Gold Bar 1,000G ×3–10.'],
  ),
  890003: ExchangeItemDetails(
    'Contains a random amount of gold bars.',
    uses: ['Open for Gold Bar 1,000G ×5–20.'],
  ),
  45124: ExchangeItemDetails(
    'Contains a random gold bar.',
    uses: ['Open for Gold Bar 1,000G, 2,000G, 3,000G, 4,000G or 5,000G.'],
  ),
  45912: ExchangeItemDetails(
    'A box of enhancement materials.',
    uses: [
      "Valks' Cry ×15",
      'Black Stone ×30',
      'Memory Fragment ×15',
      'Sharp Black Crystal Shard ×16',
    ],
  ),
  761018: ExchangeItemDetails(
    'An exchange item earned from Node Wars and world bosses.',
    uses: ['Exchange through Manage Currency.'],
  ),
  17572: ExchangeItemDetails(
    'Adds time to the Item Collection Increase Gauge.',
    uses: ['Activate the gauge while defeating monsters to increase loot.'],
  ),
  768160: ExchangeItemDetails(
    'A sealed crystal that can be opened or processed.',
    uses: [
      'Open for a random Black Magic Crystal.',
      'Heat to obtain Magical Shards.',
      'Grind to obtain Black Stone Powder.',
    ],
  ),
  59858: ExchangeItemDetails('Open to obtain a random Lightstone of Fire.'),
  59859: ExchangeItemDetails('Open to obtain a random Lightstone of Earth.'),
  59860: ExchangeItemDetails('Open to obtain a random Lightstone of Wind.'),
  59861: ExchangeItemDetails('Open to obtain a random Lightstone of Flora.'),
  45107: ExchangeItemDetails(
    'A material for Glorious Crystals of Gallantry.',
    uses: [
      "Craft Glorious Crystal of Gallantry – Ah'krad or Olucas through Simple Alchemy.",
    ],
  ),
  45105: ExchangeItemDetails(
    'A material for Glorious Crystals of Honor.',
    uses: [
      'Craft JIN, BON or WON Glorious Crystal of Honor – Max HP through Simple Alchemy.',
    ],
  ),
  45162: ExchangeItemDetails(
    'An alchemy material sold by Old Moon Managers.',
    uses: ['Craft an Old Moon Censer.', "Used for Old Moon Guild's Support."],
  ),
  45026: ExchangeItemDetails(
    'Fuel for copying equipment between tagged characters.',
    uses: ["Use with Marni's Suspicious Device in Tag Characters."],
  ),
  820152: ExchangeItemDetails(
    'A long-lasting buff for your entire Family.',
    kind: 'Consumable',
    effects: [
      'Max HP +100',
      'Max Stamina +50',
      'All Resistance +2%',
      'Max Energy +50',
      'Energy Recovery +1',
      'Weight Limit +50 LT',
      'Breath/Strength EXP +20%',
      'Heatstroke/Hypothermia Resistance +50%',
    ],
    notes: ['Duration: 90 days.'],
  ),
  11017: ExchangeItemDetails('Boss armor worn in the chest slot.'),
  752825: ExchangeItemDetails(
    'Open for one random Manos accessory.',
    uses: ['Manos Necklace', 'Manos Earring', 'Manos Ring', 'Manos Belt'],
  ),
  757004: ExchangeItemDetails(
    'A material for Mythical Horse awakening.',
    uses: [
      'Grind into Mythical Powder.',
      'Exchange with Wapra for Courser Training materials.',
    ],
  ),
  757010: ExchangeItemDetails(
    'A material for Mythical Horse awakening.',
    uses: ['Manufacture a Mythical Censer.'],
  ),
  4917: ExchangeItemDetails(
    'A material used to craft crystals.',
    uses: ['Combine with crystals and Magical Shards through Simple Alchemy.'],
  ),
  50815: ExchangeItemDetails(
    'A Courser Training material.',
    uses: ['Raises Strength training for Dream Horse awakening.'],
  ),
  50816: ExchangeItemDetails(
    'A Courser Training material.',
    uses: ['Raises Skill training for Dream Horse awakening.'],
  ),
  50817: ExchangeItemDetails(
    'A Courser Training material.',
    uses: ['Raises Elegance training for Dream Horse awakening.'],
  ),
  607185: ExchangeItemDetails(
    'Swaps progress between two characters in your Family.',
    uses: ['Exchanges Combat EXP, Skill EXP, inventory slots and weight.'],
    notes: [
      'Both characters must be at least Lv. 50 and unequip awakening weapons.',
      'Season characters cannot use it.',
      'Consumed when used; the exchange cannot be undone.',
    ],
  ),
  8042: ExchangeItemDetails(
    'A material used to make revival items.',
    uses: [
      "Simple Alchemy: Tears of War ×1 + Ancient Spirit Dust ×50 → Elion's Tear ×1.",
      "There is also a small chance of Elion's Blessing.",
    ],
    notes: ['Learn the knowledge from Vitheons Belucci in Calpheon first.'],
  ),
  4989: ExchangeItemDetails(
    'A material for Red Battlefield Crystals.',
    uses: ['Heat with a compatible crystal to make a Red Battlefield Crystal.'],
  ),
  65401: ExchangeItemDetails('Contains three Whale Tendon Potions.'),
  750490: ExchangeItemDetails(
    'A tea for life skills and training.',
    kind: 'Consumable',
    effects: [
      'Mount EXP +50%',
      'Life EXP +30%',
      'Gathering Item Drop Rate +10%',
      'Weight Limit +100 LT',
    ],
    notes: ['Duration: 180 min.', 'Cooldown: 180 min.'],
  ),
};
