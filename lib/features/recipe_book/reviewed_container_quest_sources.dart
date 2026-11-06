// Exact PC container/quest sources. See docs/reviewed-container-quest-sources.json.
// Informational only: no automatic opening, crafting, loot EV or saved-state change.
import 'recipe_book_item_info.dart';

const reviewedContainerQuestSources = <int, (String, List<String>)>{
  // Ordinary gear, not Steel Taritas or the same-name outfit identities.
  10813: ('Taritas Helmet', ['Open · Taritas Defense Gear Box (chance)']),
  10814: ('Taritas Armor', ['Open · Taritas Defense Gear Box (chance)']),
  10815: ('Taritas Gloves', ['Open · Taritas Defense Gear Box (chance)']),
  10816: ('Taritas Shoes', ['Open · Taritas Defense Gear Box (chance)']),
  16001: ("Black Stone", ["Open · Black Stone Bundle (25–50)"]),
  11002: (
    "Hercules' Might Armor",
    ["Open · Hercules' Defense Gear Box (chance)"],
  ),
  11003: (
    "Hercules' Might Gloves",
    ["Open · Hercules' Defense Gear Box (chance)"],
  ),
  11001: (
    "Hercules' Might Helmet",
    ["Open · Hercules' Defense Gear Box (chance)"],
  ),
  11006: ("Heve's Strength Armor", ["Open · Heve's Defense Gear Box (chance)"]),
  11008: ("Heve's Strength Shoes", ["Open · Heve's Defense Gear Box (chance)"]),
  11007: (
    "Heve's Strength Gloves",
    ["Open · Heve's Defense Gear Box (chance)"],
  ),
  11005: (
    "Heve's Strength Helmet",
    ["Open · Heve's Defense Gear Box (chance)"],
  ),
  692016: ("Krea Shamshir", ["Open · Krea Main Weapon Box (chance)"]),
  730516: ("Krea Morning Star", ["Open · Krea Main Weapon Box (chance)"]),
  733015: ("Krea Serenaca", ["Open · Krea Main Weapon Box (chance)"]),
  10256: ("Krea Longbow", ["Open · Krea Main Weapon Box (chance)"]),
  690518: ("Krea Battle Axe", ["Open · Krea Main Weapon Box (chance)"]),
  14456: ("Krea Staff", ["Open · Krea Main Weapon Box (chance)"]),
  732265: ("Krea Kyve", ["Open · Krea Main Weapon Box (chance)"]),
  15130: (
    "Magic Crystal of Infinity - Down Attack",
    ["Open · Magic Crystal of Infinity Box (chance)"],
  ),
  15129: (
    "Magic Crystal of Infinity - Back Attack",
    ["Open · Magic Crystal of Infinity Box (chance)"],
  ),
  15131: (
    "Magic Crystal of Infinity - Air Attack",
    ["Open · Magic Crystal of Infinity Box (chance)"],
  ),
  15106: (
    "Magic Crystal of Infinity - Armor",
    ["Open · Magic Crystal of Infinity Box (chance)"],
  ),
  15136: (
    "Magic Crystal of Infinity - Max HP",
    ["Open · Magic Crystal of Infinity Box (chance)"],
  ),
  15132: (
    "Magic Crystal of Infinity - Critical Hit",
    ["Open · Magic Crystal of Infinity Box (chance)"],
  ),
  11010: (
    "Fortuna's Luck Armor",
    ["Open · Fortuna's Luck Defense Gear Box (chance)"],
  ),
  11012: (
    "Fortuna's Luck Shoes",
    ["Open · Fortuna's Luck Defense Gear Box (chance)"],
  ),
  11011: (
    "Gloves of Fortuna's Luck",
    ["Open · Fortuna's Luck Defense Gear Box (chance)"],
  ),
  11009: (
    "Helmet of Fortuna's Luck",
    ["Open · Fortuna's Luck Defense Gear Box (chance)"],
  ),
  15216: (
    "Black Magic Crystal - Assault",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15207: (
    "Black Magic Crystal - Vigor",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15217: (
    "Black Magic Crystal - Sturdiness",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15212: (
    "Black Magic Crystal - Adamantine",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15214: (
    "Black Magic Crystal - Descent",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15224: (
    "Black Magic Crystal - Agility",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15213: (
    "Black Magic Crystal - Ascension",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15211: (
    "Black Magic Crystal - Swiftness",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15221: (
    "Black Magic Crystal - Memory",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15218: (
    "Black Magic Crystal - Valor",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15222: (
    "Black Magic Crystal - Intimidation",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15201: (
    "Black Magic Crystal - Precision",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15206: (
    "Black Magic Crystal - Armor",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  15219: (
    "Black Magic Crystal - Ensnare",
    ["Open · Sealed Black Magic Crystal (chance)"],
  ),
  11607: ("Ogre Ring", ["Open · Soiled Ogre Ring (chance)"]),
  12031: (
    "Ring of Crescent Guardian",
    ["Open · Soiled Ring of Crescent Guardian (chance)"],
  ),
  12229: ("Centaurus Belt", ["Open · Soiled Centaurus Belt (chance)"]),
  11625: ("Sicil's Necklace", ["Open · Soiled Sicil's Necklace (chance)"]),
  5862: (
    "Scorched Fragment",
    [
      "Weekly quest · Lara, Heidel (Lv. 16+): make and give 700 Potato Dough; choose 7",
      "Quest · Lara: give 14 Small Four-leaf Clovers; choose 3",
      "Quests · Black Spirit: learn all 6 Beginner or Skilled Processing knowledges (once each per Family)",
    ],
  ),
  5861: (
    "Sunset Dyed Wool",
    [
      "Weekly quest · Lara, Heidel (Lv. 16+): make and give 700 Potato Dough; choose 7",
      "Quest · Lara: give 14 Small Four-leaf Clovers; choose 3",
    ],
  ),
  4481: (
    "Gem Polisher",
    [
      "Quests · Black Spirit: learn all 6 Beginner or Skilled Processing knowledges (once each per Family)",
    ],
  ),
  6183: (
    "Leather Glaze",
    [
      "Quests · Black Spirit: learn all 6 Beginner or Skilled Processing knowledges (once each per Family)",
    ],
  ),
  4076: (
    "Metal Solvent",
    [
      "Quests · Black Spirit: learn all 6 Beginner or Skilled Processing knowledges (once each per Family)",
    ],
  ),
  4684: (
    "Plywood Hardener",
    [
      "Quests · Black Spirit: learn all 6 Beginner or Skilled Processing knowledges (once each per Family)",
    ],
  ),
};

RecipeBookItemInfo withReviewedContainerQuestSources(
  RecipeBookItemInfo info, {
  required String? itemId,
}) {
  final fact = reviewedContainerQuestSources[int.tryParse(itemId ?? '')];
  if (fact == null ||
      info.isTemporarilyArchived ||
      info.title.trim().toLowerCase() != fact.$1.toLowerCase()) {
    return info;
  }
  return info.copyWith(
    acquisitionNotes: {...info.acquisitionNotes, ...fact.$2}.toList(),
  );
}
