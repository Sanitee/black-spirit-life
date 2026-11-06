import 'superseded_boss_materials.dart';

/// Reversible availability review, not a claim that these items were removed.
/// Keep raw catalog records and saved state intact; normal choices and market
/// requests consult this policy instead of deleting historical identities.
const temporarilyArchivedItemsById = <String, String>{
  '6211': 'Monkey Blood',
  '6011': 'Monkey Hide',
  '6007': 'Dinosaur Hide',
  '15202': 'Black Magic Crystal - Power',
  '15208': 'Black Magic Crystal - Patience',
  '15209': 'Black Magic Crystal - Healing',
  '15210': 'Black Magic Crystal - Resonance',
  '15215': 'Black Magic Crystal - Endurance',
};

const temporarilyArchivedItemLabel = 'Temporarily archived';
const temporarilyArchivedItemReason = 'No current source confirmed.';

/// Exact PC NA/EU January 31, 2024 removals (groupContentNo=6545).
/// Table headings are not family-wide exclusions. Knowledge items and later
/// same-name bound identities are deliberately not included.
const removedJanuary2024CrystalsById = <String, String>{
  '15022': 'Magic Crystal - Crimson Flame',
  '15024': 'Magic Crystal - Destruction',
  '15025': 'Magic Crystal - Temptation',
  '15032': 'Magic Crystal - Meditation',
  '15023': 'Magic Crystal - Enchantment',
  '15026': 'Magic Crystal - Agony',
  '15003': 'Magic Crystal of Crimson Flame - Carnage',
  '15004': 'Magic Crystal of Crimson Flame - Carnage',
  '15005': 'Magic Crystal of Crimson Flame - Carnage',
  '15001': 'Magic Crystal of Crimson Flame - Precision',
  '15002': 'Magic Crystal of Crimson Flame - Power',
  '15009': 'Magic Crystal of Abundance - Healing',
  '15006': 'Magic Crystal of Abundance - Armor',
  '15008': 'Magic Crystal of Abundance - Patience',
  '15010': 'Magic Crystal of Abundance - Resonance',
  '15007': 'Magic Crystal of Abundance - Vigor',
  '15029': 'Magic Crystal of the Sun - Ensnare',
  '15016': 'Magic Crystal of the Sun - Valor',
  '15015': 'Magic Crystal of the Sun - Sturdiness',
  '15030': 'Magic Crystal of the Sun - Boulder',
  '15014': 'Magic Crystal of the Sun - Assault',
  '15011': 'Magic Crystal of Nature - Swiftness',
  '15013': 'Magic Crystal of Nature - Ascension',
  '15027': 'Magic Crystal of Nature - Descent',
  '15028': 'Magic Crystal of Nature - Endurance',
  '15012': 'Magic Crystal of Nature - Adamantine',
  '15018': 'Magic Crystal of Enchantment - Intimidation',
  '15017': 'Magic Crystal of Enchantment - Memory',
  '15019': 'Magic Crystal of Enchantment - Vision',
  '15020': 'Magic Crystal of Enchantment - Agility',
  '15031': 'Magic Crystal of Enchantment - Experience',
  '15103': 'Magic Crystal of Infinity - Carnage',
  '15104': 'Magic Crystal of Infinity - Carnage',
  '15105': 'Magic Crystal of Infinity - Carnage',
  '15101': 'Magic Crystal of Infinity - Precision',
  '15102': 'Magic Crystal of Infinity - Power',
  '15107': 'Magic Crystal of Infinity - Vigor',
  '15108': 'Magic Crystal of Infinity - Patience',
  '15109': 'Magic Crystal of Infinity - Healing',
  '15110': 'Magic Crystal of Infinity - Resonance',
  '15111': 'Magic Crystal of Infinity - Swiftness',
  '15112': 'Magic Crystal of Infinity - Adamantine',
  '15113': 'Magic Crystal of Infinity - Ascension',
  '15114': 'Magic Crystal of Infinity - Descent',
  '15115': 'Magic Crystal of Infinity - Endurance',
  '15116': 'Magic Crystal of Infinity - Assault',
  '15117': 'Magic Crystal of Infinity - Sturdiness',
  '15118': 'Magic Crystal of Infinity - Valor',
  '15119': 'Magic Crystal of Infinity - Ensnare',
  '15120': 'Magic Crystal of Infinity - Strength',
  '15121': 'Magic Crystal of Infinity - Memory',
  '15122': 'Magic Crystal of Infinity - Intimidation',
  '15123': 'Magic Crystal of Infinity - Vision',
  '15124': 'Magic Crystal of Infinity - Agility',
  '15126': 'Magic Crystal of Infinity - Durability',
  '15133': 'Magic Crystal of Infinity - Speed Attack',
  '15134': 'Magic Crystal of Infinity - Counter Attack',
  '15135': 'Magic Crystal of Infinity - Siege',
  '15137': 'Magic Crystal of Infinity - Melee Defense',
  '15138': 'Magic Crystal of Infinity - Ranged Defense',
  '15139': 'Magic Crystal of Infinity - Magic Defense',
  '15148': 'Magic Crystal of Infinity - Melee Attack',
  '15149': 'Magic Crystal of Infinity - Ranged Attack',
  '15150': 'Magic Crystal of Infinity - Magic Attack',
};

const removedJanuary2024CrystalReason =
    'Removed in the January 31, 2024 PC update.';

/// Official PC NA/EU August 20, 2026 cup-extraction change (10478).
/// Keep historical catalog/save identities; Mirror of Equilibrium replaced them.
const removedAugust2026CupMaterialsById = <String, String>{
  '820020': 'Fused Crystal of Emotions',
  '820021': 'Refined Essence of Emotions',
};
const removedAugust2026CupMaterialReason =
    'Removed in the August 20, 2026 PC update.';

/// Obsolete identities, including retained copies of discontinued materials.
/// This is not a prefix filter: permanent [Event] rewards remain available.
/// Evidence: docs/practical-readiness-20261103.json and
/// docs/practical-followthrough-20261104.json.
const retiredPcItemsById = <String, String>{
  '4910': 'Grade 3 Weapon Reform Stone',
  '4911': 'Grade 3 Armor Reform Stone',
  '4924': 'Mystical Spirit Powder',
  '44332': 'Vell\'s Fine Powder',
  '45333': 'Wild Spirit Stone',
  '5952': 'Trace of Despair',
  '756002': 'Frosted Black Stone',
  '756003': 'Starlight Crystal',
  '756004': 'Solar Black Stone',
  '756005': 'Lunar Black Stone',
  '757028': 'Wind Dew',
  '757029': 'Gale Black Stone',
  '800096': 'Frosty Moonlight Dew of Dawn',
  '800097': 'Morning Sun Embracing the Red Sunset',
  '800098': 'Blooming Snow Crystal of Endless Winter',
  '800099': 'Glass Bottle Shaped From a Witch\'s Red Lips',
  '800102': 'Concentrated Dawnlight',
  '820014': 'Dormant Fairy\'s Breath',
};

bool isRetiredPcItem(String name, {String? itemId}) {
  final numeric = itemId == null ? null : int.tryParse(itemId.trim());
  if (numeric != null && numeric > 0) {
    return retiredPcItemsById.containsKey('$numeric');
  }
  final folded = name.trim().toLowerCase();
  return retiredPcItemsById.values.any(
    (canonical) => canonical.toLowerCase() == folded,
  );
}

/// Confirmed PC removals, distinct from the temporary research holds above.
/// Official NA/EU September 3, 2026: groupContentNo=10550. Raw identities,
/// recipe history and saved quantities remain intact, but are not active advice.
const removedPcItemsById = <String, String>{
  // Superseded identities use the same availability gate, with their own
  // replacement label/reason. Raw catalog records and saves remain intact.
  ...supersededBossMaterialsById,
  ...removedJanuary2024CrystalsById,
  ...removedAugust2026CupMaterialsById,
  ...retiredPcItemsById,
  '5303': 'Tenacious Origin of Life',
  '5304': 'Rough Opulent Crystal',
  '5305': 'Flawless Spirit Stone',
  '45122': 'Splendid Spirit Stone of Destruction Fragment',
  '45338': 'Splendid Spirit Stone of Destruction',
  '15276': 'JIN Dawn Crystal - Life EXP',
  '15277': 'BON Dawn Crystal - Life EXP',
  '15278': 'WON Dawn Crystal - Life EXP',
};

const removedPcItemLabel = 'Removed item';
const removedPcItemReason = 'Removed in the September 3, 2026 PC update.';

String removedPcItemLabelFor(String name, {String? itemId}) =>
    bossMaterialReplacementFor(name, itemId: itemId) != null
    ? 'Replaced item'
    : isRetiredPcItem(name, itemId: itemId)
    ? 'Retired item'
    : removedPcItemLabel;

bool isRemovedJanuary2024Crystal(String name, {String? itemId}) {
  final numeric = itemId == null ? null : int.tryParse(itemId.trim());
  if (numeric != null && numeric > 0) {
    return removedJanuary2024CrystalsById.containsKey('$numeric');
  }
  final folded = name.trim().toLowerCase();
  return removedJanuary2024CrystalsById.values.any(
    (canonical) => canonical.toLowerCase() == folded,
  );
}

String removedPcItemReasonFor(String name, {String? itemId}) {
  final replacement = bossMaterialReplacementFor(name, itemId: itemId);
  if (replacement != null) {
    return 'Replaced by $replacement in the February 28, 2024 PC update.';
  }
  if (isRetiredPcItem(name, itemId: itemId)) {
    return 'No longer obtainable.';
  }
  return isRemovedJanuary2024Crystal(name, itemId: itemId)
      ? removedJanuary2024CrystalReason
      : isRemovedAugust2026CupMaterial(name, itemId: itemId)
      ? removedAugust2026CupMaterialReason
      : removedPcItemReason;
}

bool isRemovedAugust2026CupMaterial(String name, {String? itemId}) {
  final numeric = itemId == null ? null : int.tryParse(itemId.trim());
  if (numeric != null && numeric > 0) {
    return removedAugust2026CupMaterialsById.containsKey('$numeric');
  }
  final folded = name.trim().toLowerCase();
  return removedAugust2026CupMaterialsById.values.any(
    (canonical) => canonical.toLowerCase() == folded,
  );
}

bool isRemovedPcItem(String name, {String? itemId}) {
  final numeric = itemId == null ? null : int.tryParse(itemId.trim());
  if (numeric != null && numeric > 0) {
    return removedPcItemsById.containsKey('$numeric');
  }
  final folded = name.trim().toLowerCase();
  return removedPcItemsById.values.any(
    (canonical) => canonical.toLowerCase() == folded,
  );
}

/// Legacy-named common availability gate, also used for confirmed removals.
/// Keep the separate maps and [isRemovedPcItem] for truthful presentation:
/// "Removed item" is not "No current source confirmed".
bool isTemporarilyArchivedMarketItemId(String itemId) {
  final numeric = int.tryParse(itemId.trim());
  return numeric != null &&
      numeric > 0 &&
      (temporarilyArchivedItemsById.containsKey('$numeric') ||
          removedPcItemsById.containsKey('$numeric'));
}

bool isTemporarilyArchivedItem(String name, {String? itemId}) {
  final numeric = itemId == null ? null : int.tryParse(itemId.trim());
  // An explicit different identity wins over a same-name custom alias. The
  // fallback is exact folded-name matching only, never a crystal-family match.
  if (numeric != null && numeric > 0) {
    return isTemporarilyArchivedMarketItemId('$numeric');
  }
  final folded = name.trim().toLowerCase();
  return isRemovedPcItem(name, itemId: itemId) ||
      temporarilyArchivedItemsById.values.any(
        (canonical) => canonical.toLowerCase() == folded,
      );
}
