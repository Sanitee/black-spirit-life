// Reviewed PC description-backed facts, 2026-11-02.
// Exact identities and evidence: docs/reviewed-reference-facts-20261102.json.
// No inferred proc rates, automatic recipes, market eligibility or saved IDs.
import '../../domain/models/catalog_models.dart';
import '../../domain/planner/reviewed_recipe_yields.dart';
import 'recipe_book_item_info.dart';
import 'reviewed_artifact_facts.dart';
import 'reviewed_container_quest_sources.dart';
import 'reviewed_lustrous_gem_sources.dart';
import 'reviewed_monster_quest_sources.dart';
import 'reviewed_random_crystal_sources.dart';
import 'reviewed_raw_consumption.dart';
import 'reviewed_reform_recycling.dart';
import 'reviewed_weapon_recycling_sources.dart';

class ReviewedReferenceFacts {
  const ReviewedReferenceFacts(
    this.name, {
    this.sources = const [],
    this.notes = const [],
    this.effects = const [],
    this.kind,
  });
  final String name;
  final List<String> sources;
  final List<String> notes;
  final List<String> effects;
  final String? kind;
}

const reviewedReferenceFacts = <int, ReviewedReferenceFacts>{
  // Practical source steps and conditions; evidence in
  // docs/practical-completion-sources-20261104.json.
  45517: ReviewedReferenceFacts(
    "Khan's Dim Magic",
    kind: 'Quest material',
    notes: ['Three quest rewards replace one Khan\'s Concentrated Magic.'],
  ),
  9795: ReviewedReferenceFacts(
    'Blush Leaf',
    sources: ['Farming · Breed crops, prune them or remove pests.'],
  ),
  9780: ReviewedReferenceFacts(
    "Witch's Delicacy",
    sources: ['Cooking Utensil · Chance byproduct while cooking.'],
  ),
  9781: ReviewedReferenceFacts(
    'Mysterious Catalyst',
    sources: [
      'Alchemy Tool · Chance byproduct while making potions or elixirs.',
    ],
  ),
  9799: ReviewedReferenceFacts(
    'Wildspark',
    sources: ['Butcher hunted animals (chance; Hunting Mastery 250+).'],
  ),
  752530: ReviewedReferenceFacts(
    "Atanis' Element",
    sources: ["Monster drops · Look for Atanis' Element in Monster Zone Info."],
  ),
  66771: ReviewedReferenceFacts(
    'Sangpyeong Coin',
    sources: [
      'Morning Light · Story quests, daily quests and Black Shrine reward bundles.',
    ],
  ),
  820034: ReviewedReferenceFacts(
    'Essence of Taebaek',
    sources: [
      'Black Shrine - Donghae (Solo) · Chance from weekly boss reward bundles.',
    ],
  ),
  59878: ReviewedReferenceFacts(
    'Tear of Illusion',
    sources: [
      'Black Shrine - Donghae (Solo) · Weekly reward bundles; loot depends on boss and difficulty.',
    ],
  ),
  42497: ReviewedReferenceFacts(
    'Energy of Lakiaro',
    sources: ['Lakiaro minigame · Drieghan or Kamasylvia.'],
    notes: ['Use a Manos Hoe, Dostter Hoe or Dostter Steel Hoe.'],
  ),
  4917: ReviewedReferenceFacts(
    'Forest Fury',
    sources: [
      'Monster drops · Kamasylvia, including Fadus Habitat and Manshaum Forest.',
    ],
  ),
  735353: ReviewedReferenceFacts(
    "Sethra's Artifact - Gathering Item Drop Rate",
    sources: [
      'Gathering with tools (chance; not water scooping or shoveling).',
    ],
  ),
  735356: ReviewedReferenceFacts(
    "Sethra's Artifact - Gathering EXP",
    sources: [
      'Gathering with tools (chance; not water scooping or shoveling).',
    ],
  ),
  735367: ReviewedReferenceFacts(
    "Sethra's Artifact - Gathering Mastery",
    sources: [
      'Gathering with tools (chance; not water scooping or shoveling).',
    ],
  ),
  735358: ReviewedReferenceFacts(
    "Sethra's Artifact - Hunting EXP",
    sources: ['Butcher hunted animals (chance).'],
  ),
  735369: ReviewedReferenceFacts(
    "Sethra's Artifact - Hunting Mastery",
    sources: ['Butcher hunted animals (chance).'],
  ),
  735351: ReviewedReferenceFacts(
    "Sethra's Artifact - Life EXP",
    sources: [
      'Gather with tools, butcher hunted animals, or harvest/breed crops (chance).',
      'Special Barter or Life Skill bonus quests, including Imperial Delivery (chance).',
    ],
    notes: ['Gathering: not barehanded, water scooping or shoveling.'],
  ),
  735352: ReviewedReferenceFacts(
    "Sethra's Artifact - Life Skill Mastery",
    sources: [
      'Gather with tools, butcher hunted animals, or harvest/breed crops (chance).',
      'Special Barter or Life Skill bonus quests, including Imperial Delivery (chance).',
    ],
    notes: ['Gathering: not barehanded, water scooping or shoveling.'],
  ),
  // Exact current item descriptions, with official PC source corroboration.
  // Keep the same short method/input pattern as Addis; no inferred yields.
  // Evidence: docs/reviewed-specific-crafting-sources.json.
  15628: ReviewedReferenceFacts(
    'Black Magic Crystal - Harphia',
    sources: [
      'Heat Black Essence: Harphia ×1 + Ancient Magic Crystal - Harphia ×1.',
    ],
  ),
  15629: ReviewedReferenceFacts(
    'Black Magic Crystal - Cobelinus',
    sources: [
      'Heat Black Essence: Cobelinus ×1 + Ancient Magic Crystal - Cobelinus ×1.',
    ],
  ),
  15630: ReviewedReferenceFacts(
    'Black Magic Crystal - Viper',
    sources: [
      'Heat Black Essence: Viper ×1 + Ancient Magic Crystal - Viper ×1.',
    ],
  ),
  15631: ReviewedReferenceFacts(
    'Black Magic Crystal - Hystria',
    sources: [
      'Heat Black Essence: Hystria ×1 + Ancient Magic Crystal - Hystria ×1.',
    ],
  ),
  15632: ReviewedReferenceFacts(
    'Black Magic Crystal - Carmae',
    sources: [
      'Heat Black Essence: Carmae ×1 + Ancient Magic Crystal - Carmae ×1.',
    ],
  ),
  8125: ReviewedReferenceFacts(
    'Passion of Valtarra',
    sources: ["Simple Alchemy · Valtarra's Flame ×100 + Garmoth's Scale ×100"],
  ),
  // Explicit current item descriptions; these are source hints, not new
  // automatic recipes or guessed output distributions.
  // Evidence and scope: docs/reviewed-common-processing-sources.json.
  4068: ReviewedReferenceFacts(
    'Polished Stone',
    sources: ['Grind Rough Stone ×10.'],
  ),
  6159: ReviewedReferenceFacts(
    'Fine Soft Hide',
    sources: ['Dry Soft Hide ×10.'],
  ),
  4722: ReviewedReferenceFacts(
    'Snowfield Cedar Plywood',
    sources: ['Chop Snowfield Cedar Plank ×10.'],
  ),
  // These are not exchange-only items. Manufacturing guidance is shared by
  // every reference host; no gear-planning multiplier is inferred.
  // Exact recipe/replacement evidence: docs/reviewed-manos-sources.json.
  705047: ReviewedReferenceFacts(
    "Manos Alchemist's Clothes",
    sources: ['Manufacture · Processing (L)'],
    kind: 'Life skill clothing',
  ),
  16487: ReviewedReferenceFacts(
    'Manos Butcher Knife',
    sources: ['Manufacture · Processing (L)'],
    kind: 'Life skill tool',
  ),
  705037: ReviewedReferenceFacts(
    "Manos Cook's Clothes",
    sources: ['Manufacture · Processing (L)'],
    kind: 'Life skill clothing',
  ),
  705052: ReviewedReferenceFacts(
    "Manos Fisher's Clothes",
    sources: ['Manufacture · Processing (L)'],
    kind: 'Life skill clothing',
  ),
  16482: ReviewedReferenceFacts(
    'Manos Fluid Collector',
    sources: ['Manufacture · Processing (L)'],
    kind: 'Life skill tool',
  ),
  16479: ReviewedReferenceFacts(
    'Manos Hoe',
    sources: ['Manufacture · Processing (L)'],
    kind: 'Life skill tool',
  ),
  705156: ReviewedReferenceFacts(
    'Manos Riding Crop',
    sources: ['Manufacture · Processing (L)'],
    kind: 'Life skill tool',
  ),
  16486: ReviewedReferenceFacts(
    'Manos Tanning Knife',
    sources: ['Manufacture · Processing (L)'],
    kind: 'Life skill tool',
  ),
  705015: ReviewedReferenceFacts(
    "Manos Trainer's Clothes",
    sources: ['Manufacture · Processing (L)'],
    kind: 'Life skill clothing',
  ),
  // Additional current Golden Seal routes, not legacy Shiny seals or the
  // October 30 Global Lab preview. docs/reviewed-additional-seal-sources.json.
  4988: ReviewedReferenceFacts(
    'Black Essence: Addis',
    sources: [
      'Exchange · 80 Golden Seal - [Imperial Conquest] · Manage Currency',
    ],
  ),
  4995: ReviewedReferenceFacts(
    'Black Essence: Carmae',
    sources: [
      'Exchange · 80 Golden Seal - [Imperial Conquest] · Manage Currency',
    ],
  ),
  4992: ReviewedReferenceFacts(
    'Black Essence: Cobelinus',
    sources: [
      'Exchange · 80 Golden Seal - [Imperial Conquest] · Manage Currency',
    ],
  ),
  4994: ReviewedReferenceFacts(
    'Black Essence: Hystria',
    sources: [
      'Exchange · 80 Golden Seal - [Imperial Conquest] · Manage Currency',
    ],
  ),
  4993: ReviewedReferenceFacts(
    'Black Essence: Viper',
    sources: [
      'Exchange · 80 Golden Seal - [Imperial Conquest] · Manage Currency',
    ],
  ),
  4990: ReviewedReferenceFacts(
    'Black Essence: Black Spirit Crystal',
    sources: [
      'Exchange · 20 Golden Seal - [Imperial Conquest] · Manage Currency',
    ],
  ),
  16181: ReviewedReferenceFacts(
    'Spellbound Tool Box',
    sources: [
      'Exchange · 50 Golden Seal - [Imperial Conquest] · Manage Currency',
    ],
  ),
  16069: ReviewedReferenceFacts(
    'Storm Horse Gear Box',
    sources: [
      'Exchange · 1,000 Golden Seal - [Work Supervisor] · Manage Currency',
    ],
  ),
  // Unified identities survive the February 2024 simplification. Do not
  // derive a fictitious boss named "Boss" or confuse the two Aura items.
  8904: ReviewedReferenceFacts(
    'Concentrated Boss Crystal',
    sources: [
      'Boss drops',
      'Jetina · Weekly Imperfect Beings quest or Latent Boss Aura exchange',
    ],
  ),
  8917: ReviewedReferenceFacts(
    'Contained Boss Aura',
    sources: [
      'Simple Alchemy · Market-tradable boss gear, unenhanced to TRI (consumes the gear)',
    ],
    notes: ['Output: unenhanced 1, PRI 10, DUO 15, TRI 30.'],
  ),
  // Raw Amanita usability cannot be inferred from dormant buff chains either.
  // Current PC guild-boss/shrine guides and dated patches. Keep exchange
  // limits intact; docs/reviewed-resplendent-sources.json records scope.
  59858: ReviewedReferenceFacts(
    'Resplendent Lightstone of Fire',
    sources: [
      'Guild bosses · Org, Moghulis, Ferrid or Giant Mudster',
      'Black Shrine (Party) · Weekly boss and guild ranking rewards',
    ],
    notes: [
      'Guild ranking rewards need a five-player party from the same guild.',
      'Guild bosses exclude Apprentice members and War Heroes.',
    ],
  ),
  59859: ReviewedReferenceFacts(
    'Resplendent Lightstone of Earth',
    sources: [
      'Guild bosses · Org, Moghulis, Ferrid or Giant Mudster',
      'Black Shrine (Party) · Weekly guild ranking reward (Hard, top 3)',
    ],
    notes: [
      'Guild ranking rewards need a five-player party from the same guild.',
      'Guild bosses exclude Apprentice members and War Heroes.',
    ],
  ),
  59860: ReviewedReferenceFacts(
    'Resplendent Lightstone of Wind',
    sources: [
      'Black Shrine (Party) · Weekly guild ranking reward (Hard, top 10)',
    ],
    notes: [
      'Guild ranking rewards need a five-player party from the same guild.',
    ],
  ),
  59861: ReviewedReferenceFacts(
    'Resplendent Lightstone of Flora',
    sources: [
      "Guild boss · Khan at Oquilla's Eye",
      'Sea monster · Hollow Maretta in Margoria (chance)',
      'Black Shrine (Party) · Weekly guild ranking reward (Hard, top 25)',
    ],
    notes: [
      'Guild ranking rewards need a five-player party from the same guild.',
      'Guild bosses exclude Apprentice members and War Heroes.',
    ],
  ),
  17849: ReviewedReferenceFacts(
    'Advice of Valks (+50)',
    sources: [
      'Guild bosses · Org, Moghulis, Ferrid or Giant Mudster (chance)',
      'Guild bosses · Gumiho and Duoksini treasure chest (chance)',
    ],
    notes: ['Guild bosses exclude Apprentice members and War Heroes.'],
  ),
  17899: ReviewedReferenceFacts(
    'Advice of Valks (+100)',
    sources: [
      'Guild bosses · Org, Moghulis, Ferrid or Giant Mudster (chance)',
      'Guild bosses · Gumiho and Duoksini treasure chest (chance)',
    ],
    notes: ['Guild bosses exclude Apprentice members and War Heroes.'],
  ),
  // Chance-only sources, not independent guaranteed recipes. Preserve the
  // grade-specific route: juice conversion is not the same as raw-crop input.
  // Evidence and the unresolved Refined Grain Juice exception:
  // docs/reviewed-processing-byproduct-sources.json.
  4052: ReviewedReferenceFacts(
    'Iron Ingot',
    sources: [
      'Heating · Extra from Iron Ore at higher Processing levels (chance)',
    ],
  ),
  567: ReviewedReferenceFacts(
    'Concentrated Grain Juice',
    sources: ['Simple Cooking · Extra when making Grain Juice (chance)'],
  ),
  568: ReviewedReferenceFacts(
    'Highly Concentrated Grain Juice',
    sources: [
      'Simple Cooking · Extra from high-quality grain + Mineral Water (chance)',
    ],
  ),
  570: ReviewedReferenceFacts(
    'Concentrated Herbal Juice',
    sources: ['Simple Alchemy · Extra when making Herbal Juice (chance)'],
  ),
  571: ReviewedReferenceFacts(
    'Highly Concentrated Herbal Juice',
    sources: [
      'Simple Alchemy · Extra from high-quality herbs + Mineral Water (chance)',
    ],
  ),
  579: ReviewedReferenceFacts(
    'Refined Herbal Juice',
    sources: [
      'Simple Alchemy · Extra from Special herbs + Mineral Water (chance)',
    ],
  ),
  // Ordinary monster-drop stones, not the separately crafted Sharp+ family.
  // Official PC source scope: docs/reviewed-spirit-stone-sources.json.
  45298: ReviewedReferenceFacts(
    'Destruction Spirit Stone',
    sources: ['Monster drops · Kamasylvia'],
  ),
  45300: ReviewedReferenceFacts(
    'Guardian Spirit Stone',
    sources: ['Monster drops · Kamasylvia'],
  ),
  45302: ReviewedReferenceFacts(
    'Life Spirit Stone',
    sources: ['Monster drops · Kamasylvia'],
  ),
  // Mount-food crops are not covered by the ordinary plant-source generator.
  // Exact seed grades and scope: docs/reviewed-carrot-sources.json.
  54004: ReviewedReferenceFacts(
    'High-quality Carrot',
    sources: [
      'Garden · Grow from High-quality Carrot seeds',
      'Seeds · Buy matching seeds on the market, or breed carrots (chance)',
    ],
  ),
  54005: ReviewedReferenceFacts(
    'Special Carrot',
    sources: [
      'Garden · Grow from Special, Magical, or Mysterious Carrot seeds',
      'Starter seeds · Buy Special Carrot seeds on the market, or breed carrots (chance)',
    ],
  ),
  // Conditional shop guidance only: docs/reviewed-patrigio-stones.json.
  16001: ReviewedReferenceFacts(
    'Black Stone',
    sources: [
      'Patrigio · Random night-shop offer (22:00–07:00 game time)',
      'Secret Shop · 50 Energy per roll; Silver price varies',
    ],
  ),
  // Exact recycling routes: docs/reviewed-dawn-recycling.json.
  820979: ReviewedReferenceFacts(
    'Essence of Dawn',
    sources: [
      'Heating · 1 AP Dawn crystal gives 1 (WON), 10 (BON), or 30 (JIN/HAN)',
      'Heating · 1 Essence of Ascent - Accessory → 30',
      'Exchange · Specialized Essences of Dawn → this one (1:1, Dalishain)',
    ],
    notes: [
      "Accessory heating needs eligible TET/PEN gear and 1 Dawn's Aura.",
      'Heating a HAN Dawn crystal also returns 100 Crystallized Energy of Endtimes.',
    ],
  ),
  820980: ReviewedReferenceFacts(
    "Essence of Dawn - Black Spirit's Rage",
    sources: [
      "Heating · 1 Black Spirit's Rage Dawn crystal gives 1 (WON), 10 (BON), or 350 (JIN/HAN)",
    ],
    notes: [
      "Accessory heating needs eligible TET/PEN gear and 1 Dawn's Aura.",
      'Heating a HAN Dawn crystal also returns 100 Crystallized Energy of Endtimes.',
    ],
  ),
  820981: ReviewedReferenceFacts(
    'Essence of Dawn - Accuracy',
    sources: [
      'Heating · 1 Accuracy Dawn crystal gives 1 (WON), 10 (BON), or 450 (JIN/HAN)',
    ],
    notes: [
      "Accessory heating needs eligible TET/PEN gear and 1 Dawn's Aura.",
      'Heating a HAN Dawn crystal also returns 100 Crystallized Energy of Endtimes.',
    ],
  ),
  820982: ReviewedReferenceFacts(
    'Essence of Dawn - Damage Reduction',
    sources: [
      'Heating · 1 Damage Reduction Dawn crystal gives 1 (WON), 10 (BON), or 250 (JIN/HAN)',
    ],
    notes: [
      "Accessory heating needs eligible TET/PEN gear and 1 Dawn's Aura.",
      'Heating a HAN Dawn crystal also returns 100 Crystallized Energy of Endtimes.',
    ],
  ),
  820983: ReviewedReferenceFacts(
    'Essence of Dawn - Evasion',
    sources: [
      'Heating · 1 Evasion Dawn crystal gives 1 (WON), 10 (BON), or 450 (JIN/HAN)',
    ],
    notes: [
      "Accessory heating needs eligible TET/PEN gear and 1 Dawn's Aura.",
      'Heating a HAN Dawn crystal also returns 100 Crystallized Energy of Endtimes.',
    ],
  ),
  821252: ReviewedReferenceFacts(
    'Crystallized Energy of Endtimes',
    sources: [
      'Heating · 1 HAN Dawn crystal → 100 (plus its matching Essence of Dawn)',
    ],
  ),
  // Exact special sources: docs/reviewed-special-gathering-sources.json.
  4724: ReviewedReferenceFacts(
    'Caphras Tree Plank',
    sources: ['Gather · Chop Caphras trees in Edania (chance)'],
  ),
  6173: ReviewedReferenceFacts(
    'Supreme Lightweight Plume',
    sources: ['Hunting · Butcher [Oblivious] Breoro (chance)'],
  ),
  6168: ReviewedReferenceFacts(
    'Supreme Tough Hide',
    sources: ['Hunting · Butcher [Dastardly] Hyena (chance)'],
  ),
  // Gathering material list + exact client identities: docs/reviewed-gathering-material-sources.json.
  4680: ReviewedReferenceFacts(
    'Acacia Plank',
    sources: ['Gather · Chop Acacia trees (chance)'],
  ),
  4651: ReviewedReferenceFacts(
    'Ash Plank',
    sources: ['Gather · Chop Ash trees (chance)'],
  ),
  4660: ReviewedReferenceFacts(
    'Birch Plank',
    sources: ['Gather · Chop Birch trees (chance)'],
  ),
  4666: ReviewedReferenceFacts(
    'Cedar Plank',
    sources: ['Gather · Chop Cedar trees (chance)'],
  ),
  5851: ReviewedReferenceFacts(
    'Cotton Yarn',
    sources: ['Gather · Pick Cotton (chance)'],
  ),
  4463: ReviewedReferenceFacts(
    'Diamond',
    sources: ['Mining · Gem deposits (chance)'],
  ),
  4673: ReviewedReferenceFacts(
    'Elder Tree Plank',
    sources: ['Gather · Chop Elder trees (chance)'],
  ),
  4460: ReviewedReferenceFacts(
    'Emerald',
    sources: ['Mining · Gem deposits (chance)'],
  ),
  6158: ReviewedReferenceFacts(
    'Fancy Feather',
    sources: ['Tanning · Skin certain animals (chance)'],
  ),
  6156: ReviewedReferenceFacts(
    'Fancy Reptile Skin',
    sources: ['Tanning · Skin certain animals (chance)'],
  ),
  4663: ReviewedReferenceFacts(
    'Fir Plank',
    sources: ['Gather · Chop Fir trees (chance)'],
  ),
  5802: ReviewedReferenceFacts('Flax', sources: ['Gather · Pick Wild Flax']),
  5852: ReviewedReferenceFacts(
    'Flax Thread',
    sources: ['Gather · Pick Wild Flax (chance)'],
  ),
  6153: ReviewedReferenceFacts(
    'Hard Hide',
    sources: ['Tanning · Skin certain animals (chance)'],
  ),
  6157: ReviewedReferenceFacts(
    'Lightweight Plume',
    sources: ['Tanning · Skin certain animals (chance)'],
  ),
  4697: ReviewedReferenceFacts(
    'Loopy Tree Plank',
    sources: ['Gather · Chop Loopy trees (chance)'],
  ),
  4654: ReviewedReferenceFacts(
    'Maple Plank',
    sources: ['Gather · Chop Maple trees (chance)'],
  ),
  4057: ReviewedReferenceFacts(
    'Melted Copper Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4254: ReviewedReferenceFacts(
    'Melted Gold Shard',
    sources: [
      'Mining · Certain rocks and ore deposits (chance)',
      'Heat Alluvial Gold (not included in planning).',
    ],
  ),
  4051: ReviewedReferenceFacts(
    'Melted Iron Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4054: ReviewedReferenceFacts(
    'Melted Lead Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4262: ReviewedReferenceFacts(
    'Melted Mythril Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4088: ReviewedReferenceFacts(
    'Melted Nickel Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4085: ReviewedReferenceFacts(
    'Melted Noc Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4257: ReviewedReferenceFacts(
    'Melted Platinum Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4251: ReviewedReferenceFacts(
    'Melted Silver Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4060: ReviewedReferenceFacts(
    'Melted Tin Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4081: ReviewedReferenceFacts(
    'Melted Titanium Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4078: ReviewedReferenceFacts(
    'Melted Vanadium Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4063: ReviewedReferenceFacts(
    'Melted Zinc Shard',
    sources: ['Mining · Certain rocks and ore deposits (chance)'],
  ),
  4694: ReviewedReferenceFacts(
    'Moss Tree Plank',
    sources: ['Gather · Chop Moss trees (chance)'],
  ),
  4670: ReviewedReferenceFacts(
    'Palm Plank',
    sources: ['Gather · Chop Palm trees (chance)'],
  ),
  4657: ReviewedReferenceFacts(
    'Pine Plank',
    sources: ['Gather · Chop Pine trees (chance)'],
  ),
  4451: ReviewedReferenceFacts(
    'Ruby',
    sources: ['Mining · Gem deposits (chance)'],
  ),
  4454: ReviewedReferenceFacts(
    'Sapphire',
    sources: ['Mining · Gem deposits (chance)'],
  ),
  5803: ReviewedReferenceFacts(
    'Silkworm Cocoon',
    sources: ['Gather · Mulberry trees'],
  ),
  4721: ReviewedReferenceFacts(
    'Snowfield Cedar Plank',
    sources: ['Gather · Chop Snowfield Cedar trees (chance)'],
  ),
  6151: ReviewedReferenceFacts(
    'Soft Hide',
    sources: ['Tanning · Skin certain animals (chance)'],
  ),
  6155: ReviewedReferenceFacts(
    'Thick Fur',
    sources: ['Tanning · Skin certain animals (chance)'],
  ),
  6154: ReviewedReferenceFacts(
    'Thin Hide',
    sources: ['Tanning · Skin certain animals (chance)'],
  ),
  4710: ReviewedReferenceFacts(
    'Thornwood Plank',
    sources: ['Gather · Chop Thornwood trees (chance)'],
  ),
  4701: ReviewedReferenceFacts(
    'Thuja Plank',
    sources: ['Gather · Chop Thuja trees (chance)'],
  ),
  4457: ReviewedReferenceFacts(
    'Topaz',
    sources: ['Mining · Gem deposits (chance)'],
  ),
  6152: ReviewedReferenceFacts(
    'Tough Hide',
    sources: ['Tanning · Skin certain animals (chance)'],
  ),
  4676: ReviewedReferenceFacts(
    'White Cedar Plank',
    sources: ['Gather · Chop White Cedar trees (chance)'],
  ),
  766001: ReviewedReferenceFacts(
    'Purified Lightstone of Fire',
    sources: ['Dalishain · 1 Imperfect Lightstone of Fire + 20m Silver → 1'],
    notes: [
      'Alchemy Guru 1+. Makes 1, sometimes 2.',
      reviewedLightstoneYieldNote,
    ],
  ),
  766011: ReviewedReferenceFacts(
    'Purified Lightstone of Earth',
    sources: ['Dalishain · 1 Imperfect Lightstone of Earth + 20m Silver → 1'],
    notes: [
      'Alchemy Guru 1+. Makes 1, sometimes 2.',
      reviewedLightstoneYieldNote,
    ],
  ),
  766021: ReviewedReferenceFacts(
    'Purified Lightstone of Wind',
    sources: ['Dalishain · 1 Imperfect Lightstone of Wind + 20m Silver → 1'],
    notes: [
      'Alchemy Guru 1+. Makes 1, sometimes 2.',
      reviewedLightstoneYieldNote,
    ],
  ),
  766031: ReviewedReferenceFacts(
    'Purified Lightstone of Flora',
    sources: ['Dalishain · 1 Imperfect Lightstone of Flora + 20m Silver → 1'],
    notes: [
      'Alchemy Guru 1+. Makes 1, sometimes 2.',
      reviewedLightstoneYieldNote,
    ],
  ),
  // Exact source scope/evidence: docs/reviewed-gathering-lightstones.json.
  5960: ReviewedReferenceFacts(
    'Trace of Nature',
    sources: ['Gathering · Sometimes drops as an extra'],
  ),
  721003: ReviewedReferenceFacts(
    'Caphras Stone',
    sources: [
      'Gathering · Sometimes drops as an extra',
      'Monster drops and quest rewards.',
    ],
  ),
  5000: ReviewedReferenceFacts(
    'Black Gem',
    sources: ['Hunting · Butcher hunted animals (chance)'],
  ),
  4987: ReviewedReferenceFacts(
    'Concentrated Magical Black Gem',
    sources: ['Hunting · Butcher hunted animals (rare)'],
  ),
  766107: ReviewedReferenceFacts(
    'Imperfect Lightstone of Flora',
    sources: [
      'Life Skills · Gathering, Fishing, Farming and more (chance)',
      'Exchange · 10,000 Golden Seal - [Work Supervisor]',
    ],
    notes: ['No drops from barehanded gathering, water scooping or shoveling.'],
  ),
  // Exact recycling quantities, not average yields or automatic salvage.
  // Evidence and excluded unopened identities: reviewed-sea-origin-recycling.
  8105: ReviewedReferenceFacts(
    'Origin of Eltro',
    sources: [
      'Simple Alchemy · 1 unwanted Eltro Sea Crystal → 1–2 Origins (consumes the crystal)',
    ],
  ),
  8106: ReviewedReferenceFacts(
    'Origin of Serni',
    sources: [
      'Simple Alchemy · 1 unwanted Serni Sea Crystal → 1–2 Origins (consumes the crystal)',
    ],
  ),
  8108: ReviewedReferenceFacts(
    'Origin of Margoria',
    sources: [
      'Simple Alchemy · 1 unwanted Margoria Sea Crystal → 1–2 Origins (consumes the crystal)',
      'Blue Sea Crystal Box · Crow Coin Shop; 5,000 Crow Coins, 3 boxes/week (chance of 1–2)',
    ],
  ),
  8107: ReviewedReferenceFacts(
    'Origin of Zulatia',
    sources: [
      'Simple Alchemy · 1 unwanted Zulatia Sea Crystal → 1–2 Origins (consumes the crystal)',
      'Blue Sea Crystal Box · Crow Coin Shop; 5,000 Crow Coins, 3 boxes/week (chance of 1–2)',
    ],
  ),
  821169: ReviewedReferenceFacts(
    'Origin of Rusalka',
    sources: [
      'Simple Alchemy · 1 unwanted Rusalka Sea Crystal → 1 Origin (consumes the crystal)',
      'Blue Sea Crystal Box · Crow Coin Shop; 5,000 Crow Coins, 3 boxes/week (chance of 1–2)',
    ],
  ),
  757032: ReviewedReferenceFacts(
    "Stonetail Wind's Meal",
    kind: 'Food',
    effects: [
      'Mount EXP +10%',
      'Training EXP +20%',
      'All Life Skill Mastery +25',
      'Health EXP +150 (instant; not while Satiated)',
    ],
    notes: [
      'Duration: 600 min.',
      'Cooldown: 30 min.',
      'Replaces other food effects, except Health EXP.',
      'Only the last high-quality food applies; effects do not stack.',
    ],
  ),
  // Exact newly used ingredient, from the current PC item5443 description.
  5443: ReviewedReferenceFacts(
    'Insectivore Plant Root',
    sources: [
      'Monster drops · Poisonous Plants in Naga Marsh',
      'Central Market',
    ],
  ),
  5601: ReviewedReferenceFacts(
    'Insectivore Plant Powder',
    sources: [
      'Grinding · 5 Insectivore Plant Flower or 5 Insectivore Plant Leaf',
      'Gather · Insectivore Plant (hands or hoe; high Gathering Mastery required)',
    ],
  ),
  5602: ReviewedReferenceFacts(
    'Insectivore Plant Sap',
    sources: [
      'Grinding · 5 Insectivore Plant Stalk or 5 Insectivore Plant Root',
      'Gather · Insectivore Plant (fluid collector; high Gathering Mastery required)',
    ],
  ),
  4998: ReviewedReferenceFacts(
    'Sharp Black Crystal Shard',
    sources: [
      "Grinding · Pilgrim's Stone or Pilgrim's Cracked Stone (Guild Drill; chance)",
      'Patrigio · Random night-shop offer (22:00–07:00 game time)',
      'Secret Shop · 50 Energy per roll; Silver price varies',
    ],
  ),
  752023: ReviewedReferenceFacts(
    'Mass of Pure Magic',
    sources: [
      "Grinding · Pilgrim's Stone or Pilgrim's Cracked Stone (Guild Drill; chance)",
    ],
  ),
  566: ReviewedReferenceFacts(
    "Grain Juice",
    sources: ["Simple Cooking · 3 grain + 1 Mineral Water"],
    notes: ["Concentrated Grain Juice can also appear (chance)."],
    effects: [],
  ),
  569: ReviewedReferenceFacts(
    "Herbal Juice",
    sources: ["Simple Alchemy · 3 Wild Herb or 10 Weeds + 1 Mineral Water"],
    notes: ["Concentrated Herbal Juice can also appear (chance)."],
    effects: [],
  ),
  4260: ReviewedReferenceFacts(
    "Polished Opal",
    sources: ["Heating · 5 Rough Opal"],
    notes: [],
    effects: [],
  ),
  4466: ReviewedReferenceFacts(
    "Translucent Crystal",
    sources: ["Heating · 5 Rough Translucent Crystal"],
    notes: [],
    effects: [],
  ),
  4485: ReviewedReferenceFacts(
    "Violet Crystal",
    sources: ["Heating · 5 Rough Violet Crystal"],
    notes: [],
    effects: [],
  ),
  7751: ReviewedReferenceFacts(
    "Damaged Hide",
    sources: ["Hunting · Butcher hunted wild animals"],
    notes: [],
    effects: [],
  ),
  7752: ReviewedReferenceFacts(
    "Usable Hide",
    sources: ["Hunting · Butcher hunted wild animals"],
    notes: [],
    effects: [],
  ),
  5409: ReviewedReferenceFacts(
    "Dwarf Mushroom",
    sources: ["Gather · Pick Dwarf Mushrooms by hand or with a hoe"],
    notes: [],
    effects: [],
  ),
  40760: ReviewedReferenceFacts(
    "Blood Wolf's Oath",
    sources: ["Monster drops · Blood Wolf Settlement (chance)"],
    notes: [],
    effects: [],
  ),
  40762: ReviewedReferenceFacts(
    "Dragon's Fang",
    sources: ["Monster drops · Sherekhan Necropolis (chance)"],
    notes: [],
    effects: [],
  ),
  40752: ReviewedReferenceFacts(
    "Katzvariak's Venom",
    sources: ["Monster drops · Tshira Ruins (chance)"],
    notes: [],
    effects: [],
  ),
  40756: ReviewedReferenceFacts(
    "Narc's Solace",
    sources: ["Monster drops · Manshaum Forest (chance)"],
    notes: [],
    effects: [],
  ),
  40758: ReviewedReferenceFacts(
    "Tranquil Tinniolum",
    sources: ["Monster drops · Forest Ronaros (chance)"],
    notes: [],
    effects: [],
  ),
  40754: ReviewedReferenceFacts(
    "Valtarra's Memory",
    sources: ["Tanning · Navarn Steppe animals (chance)"],
    notes: [],
    effects: [],
  ),
  66191: ReviewedReferenceFacts(
    "Powder of Ascension",
    sources: ["Gather · Tanning (chance)"],
    notes: [],
    effects: [],
  ),
  820015: ReviewedReferenceFacts(
    "Nadia Rowen's Special Sauce",
    sources: ["NPC · Food Vendor"],
    notes: ["Using it for meal batches requires Cooking Skilled 1+."],
    effects: [],
  ),
  9008: ReviewedReferenceFacts(
    "Sun-Dried Salt",
    sources: ["NPC · Food Vendor or Innkeeper"],
    notes: [],
    effects: [],
  ),
  16080: ReviewedReferenceFacts(
    "Cron Stone",
    sources: ["NPC · Blacksmith · 3,000,000 Silver each"],
    notes: [],
    effects: [],
  ),
  45162: ReviewedReferenceFacts(
    "Old Moon Alchemy Catalyst",
    sources: ["NPC · Old Moon Manager · 3,500,000 Silver each"],
    notes: [],
    effects: [],
  ),
  766042: ReviewedReferenceFacts(
    "Purified Lightstone",
    sources: ["Central Market", 'Dalishain · Exchange 3 spare Lightstones → 1'],
    notes: [
      'For bulk artifact exchanges, put spares before socketed artifacts in Inventory.',
    ],
    effects: [],
  ),
  15112: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Adamantine",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Knockback/Floating Resistance +10%"],
  ),
  15124: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Agility",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["All Evasion +8"],
  ),
  15131: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Air Attack",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Air Attack Extra Damage +10%"],
  ),
  15113: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Ascension",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Jump Height +35"],
  ),
  15116: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Assault",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Attack Speed +2"],
  ),
  15103: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Carnage",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Extra AP Against Demihumans +2"],
  ),
  15134: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Counter Attack",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Counter Attack Extra Damage +10%"],
  ),
  15114: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Descent",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Fall Damage -15%"],
  ),
  15130: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Down Attack",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Down Attack Extra Damage +10%"],
  ),
  15126: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Durability",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Durability Reduction Resistance +10%"],
  ),
  15115: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Endurance",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Max Stamina +150"],
  ),
  15146: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Energy",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Max Energy +10"],
  ),
  15119: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Ensnare",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["All Accuracy +8"],
  ),
  15127: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - HP Recovery",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Recover 3 HP on Hits"],
  ),
  15109: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Healing",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["HP Recovery +3"],
  ),
  15122: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Intimidation",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Knockdown/Bound Resistance +10%"],
  ),
  15128: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - MP Recovery",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Recover 3 MP/WP/SP on Hits"],
  ),
  15150: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Magic Attack",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Magic AP +2"],
  ),
  15139: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Magic Defense",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Magic Damage Reduction +2"],
  ),
  15136: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Max HP",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Max HP +750"],
  ),
  15148: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Melee Attack",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Melee AP +2"],
  ),
  15137: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Melee Defense",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Melee Damage Reduction +2"],
  ),
  15121: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Memory",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Casting Speed +2"],
  ),
  15108: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Patience",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Max MP/WP/SP +35"],
  ),
  15102: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Power",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["All AP +2"],
  ),
  15101: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Precision",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["All Accuracy +8"],
  ),
  15149: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Ranged Attack",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Ranged AP +2"],
  ),
  15138: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Ranged Defense",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Ranged Damage Reduction +2"],
  ),
  15110: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Resonance",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["MP/WP/SP Recovery +3"],
  ),
  15133: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Speed Attack",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Speed Attack Extra Damage +10%"],
  ),
  15120: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Strength",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Weight Limit +15 LT"],
  ),
  15147: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Submergence",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Underwater Breathing +15 sec"],
  ),
  15111: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Swiftness",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Movement Speed +2"],
  ),
  15118: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Valor",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Critical Hit +2"],
  ),
  15107: ReviewedReferenceFacts(
    "Magic Crystal of Infinity - Vigor",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Max HP +35"],
  ),
  15021: ReviewedReferenceFacts(
    "Magic Crystal of Perfection",
    sources: [],
    notes: [
      "Effects apply while equipped in an active crystal preset.",
      "High chance of shattering on death.",
    ],
    effects: ["Luck +1"],
  ),
};

// These existing reference-only catalog labels deliberately have no market ID.
// Do not assign a tradable ID to bound armor, or guess its defense/evasion choice.
// Official PC July 30 rewards, August 6 journal changes and October 22 quest
// changes are combined here. Exact recipe role/group guards exclude user items.
const reviewedUnlistedReferenceSources = <String, List<String>>{
  // NA/EU May 29, 2025 + current quest/box; not expired coupon availability.
  'Ancient Hammer': [
    'Quest · Atoraxxion Final Selection Box (pick one; once per Family)',
  ],
  'Primordial Hammer': [
    'Quest · Atoraxxion Final Selection Box (pick one; once per Family)',
  ],
  'Ancient Hammer - PEN (V)': [
    "Adventure Log · Emma Bartali's Journal, chapters 2 and 5 (once per Family)",
  ],
  'Ancient Hammer - HEX (VI)': [
    "Adventure Log · Emma Bartali's Journal, chapters 8 and 11 (once per Family)",
  ],
  'Ancient Black Stone - PEN (V)': [
    "Adventure Log · Emma Bartali's Journal, chapters 3 and 6 (once per Family)",
  ],
  'Ancient Black Stone - HEX (VI)': [
    "Adventure Log · Emma Bartali's Journal, chapters 9 and 12 (once per Family)",
  ],
  'Ancient Black Stone - SEP (VII)': [
    "Adventure Log · Emma Bartali's Journal, chapter 13 (once per Family)",
  ],
  'Obsidian Hammer': [
    'Olvia Academy · Combat course rewards (4 in total, once per Family)',
  ],
  "Labreska's Helmet (Bound)": [
    'Quest · Black Spirit Support: Golden Pig King, Calamity 1',
  ],
  "Fallen God's Armor (Bound)": [
    'Quest · Black Spirit Support: Apex Changui, Calamity 1',
  ],
  "Dahn's Gloves (Bound)": [
    'Quest · Black Spirit Support: Sangoon, Calamity 1',
  ],
  "Ator's Shoes (Bound)": ['Quest · Black Spirit Support: Gumiho, Calamity 1'],
};

RecipeBookItemInfo withReviewedUnlistedReferenceSources(
  RecipeBookItemInfo info, {
  required Recipe? recipe,
}) {
  final sources = reviewedUnlistedReferenceSources[info.title];
  if (sources == null ||
      info.isTemporarilyArchived ||
      recipe == null ||
      recipe.name != info.title ||
      !recipe.isReferenceOnly ||
      recipe.group != 'Reference - Patch Items' ||
      recipe.marketId != null) {
    return info;
  }
  return info.copyWith(
    acquisitionNotes: {...info.acquisitionNotes, ...sources}.toList(),
    notes: {
      ...info.notes,
      if (info.title == 'Ancient Hammer' || info.title == 'Primordial Hammer')
        'Finish all Atoraxxion story quests; choose Ancient or Primordial Hammer.',
      if (info.title == "Dahn's Gloves (Bound)" ||
          info.title == "Ator's Shoes (Bound)")
        'Reward choice: Damage Reduction or Evasion version.',
      if (info.title.endsWith('(Bound)')) ...[
        'Requires 300+ AP and the related Morning Light story quests (Family progress).',
        'One-time Family quest reward; cannot be sold on the Central Market.',
      ],
    }.toList(),
  );
}

RecipeBookItemInfo withReviewedReferenceFacts(
  RecipeBookItemInfo info, {
  required String? itemId,
}) {
  info = withReviewedRawConsumption(info, itemId: itemId);
  info = withReviewedContainerQuestSources(info, itemId: itemId);
  info = withReviewedMonsterQuestSources(info, itemId: itemId);
  info = withReviewedLustrousGemSources(info, itemId: itemId);
  info = withReviewedRandomCrystalSources(info, itemId: itemId);
  info = withReviewedReformRecycling(info, itemId: itemId);
  info = withReviewedWeaponRecyclingSources(info, itemId: itemId);
  info = withReviewedArtifactFacts(info, itemId: itemId);
  // The current NA/EU Processing guide requires wind for Filtering. Apply the
  // same short condition to every formula; Fine Lightweight Plume currently
  // exposes a reviewed source hint rather than an automatic recipe.
  const filteringMaterials = {
    '6158': 'Fancy Feather',
    '6166': 'Fine Fancy Feather',
    '6165': 'Fine Lightweight Plume',
    '6157': 'Lightweight Plume',
    '6656': 'Purified Water',
  };
  if (!info.isTemporarilyArchived &&
      filteringMaterials[itemId] == info.title &&
      !info.notes.contains('Filtering requires wind.')) {
    info = info.copyWith(
      notes: {...info.notes, 'Filtering requires wind.'}.toList(),
    );
  }
  // Dried-fish sources already carry this condition inline. Keep all other
  // current Drying references equally clear without duplicating that text.
  const dryingMaterials = {
    '9062': 'Cheese',
    '6156': 'Fancy Reptile Skin',
    '6164': 'Fine Fancy Reptile Skin',
    '6161': 'Fine Hard Hide',
    '6159': 'Fine Soft Hide',
    '6163': 'Fine Thick Fur',
    '6162': 'Fine Thin Hide',
    '6160': 'Fine Tough Hide',
    '7918': 'Fragrant Jerky',
    '6153': 'Hard Hide',
    '5827': 'Moon Scale Plywood',
    '5809': 'Moon Vein Flax Fabric',
    '6151': 'Soft Hide',
    '6155': 'Thick Fur',
    '6154': 'Thin Hide',
    '6152': 'Tough Hide',
  };
  const dryingCondition = 'Drying: clear weather, on land.';
  if (!info.isTemporarilyArchived &&
      dryingMaterials[itemId] == info.title &&
      !info.notes.contains(dryingCondition)) {
    info = info.copyWith(notes: {...info.notes, dryingCondition}.toList());
  }
  // This is the catalyst's requirement, not the item's normal recipe level or
  // Processing level. Keep the qualification on every matching shared recipe.
  const bulkRequirement =
      "Batches using Ibellab's Essence require Alchemy Skilled 1+.";
  if (!info.isTemporarilyArchived &&
      info.acquisitionFormulas.any(
        (formula) =>
            formula.method == 'Simple Alchemy' &&
            formula.ingredients.any(
              (input) =>
                  input.name == "Ibellab's Essence" && input.quantity > 0,
            ),
      )) {
    info = info.copyWith(notes: {...info.notes, bulkRequirement}.toList());
  }
  final facts = reviewedReferenceFacts[int.tryParse(itemId ?? '')];
  if (facts == null ||
      info.isTemporarilyArchived ||
      info.title.trim().toLowerCase() != facts.name.toLowerCase()) {
    return info;
  }
  List<String> merged(List<String> existing, List<String> added) =>
      {...existing, ...added}.toList();
  // Replace only exact older source lines superseded by a qualified fact.
  // Preserve other sources and user notes; never use a generic substring match.
  final supersededSources = switch (int.tryParse(itemId ?? '')) {
    9795 => {'Farming'},
    9780 => {'Cooking'},
    9781 => {'Alchemy'},
    9799 => {'Hunting'},
    752530 => {'Combat in selected monster zones'},
    66771 => {'Land of the Morning Light'},
    820034 || 59878 => {'Defeat a boss in the Land of the Morning Light.'},
    42497 => {'Lakiaro gathering'},
    735353 || 735356 || 735367 => {'All Gathering activities.'},
    735358 || 735369 => {'All Hunting activities.'},
    735351 || 735352 => {'All Life Skill activities.'},
    4068 || 15628 || 15629 || 15630 || 15631 || 15632 => {
      'Use the Processing method listed in Crafting Notes.',
      'Processing · See Crafting Notes',
    },
    8125 => {'Use Simple Alchemy with the recipe shown in Crafting Notes.'},
    4990 => {'Exchange Golden Seals via the Manage Currency UI.'},
    8904 => {
      "Defeat Boss through its available boss encounter, or complete Jetina's weekly Imperfect Beings quest.",
    },
    8917 => {
      'Use Simple Alchemy on Boss gear; higher enhancement levels yield more Concentrated Aura.',
    },
    766107 => {'Life Skill activities according to a set probability.'},
    5601 => {'Gather Insectivore Plant with Bare Hands or a Hoe.'},
    5602 => {'Fluid Collector · Insectivore Plant'},
    8105 => {
      'Use Simple Alchemy on an unwanted Eltro sea crystal only when deliberately converting it.',
    },
    8106 => {
      'Use Simple Alchemy on an unwanted Serni sea crystal only when deliberately converting it.',
    },
    8108 => {
      'Use Simple Alchemy on an unwanted Margoria sea crystal only when deliberately converting it.',
    },
    8107 => {
      'It can also be one of the random contents of a Blue Sea Crystal Box from the Crow Coin Shop.',
      'Use Simple Alchemy on a Zulatia Sea Crystal to obtain Origin of Zulatia.',
    },
    821169 => {
      'Use Simple Alchemy on an unwanted Rusalka sea crystal only when deliberately converting it.',
    },
    _ => <String>{},
  };
  return info.copyWith(
    kind: facts.kind ?? info.kind,
    acquisitionNotes: merged(
      info.acquisitionNotes
          .where((line) => !supersededSources.contains(line))
          .toList(),
      facts.sources
          .where(
            (line) =>
                line != 'Central Market' ||
                !info.acquisitionNotes.any(
                  (old) => old.toLowerCase().contains('market'),
                ),
          )
          .toList(),
    ),
    effects: merged(info.effects, facts.effects),
    notes: merged(info.notes, facts.notes),
  );
}
