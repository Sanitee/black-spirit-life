// Historical client metadata from docs/reviewed-raw-consumption.json.
// These chains do not establish that an item is currently usable. Keep them
// available for research, but never project them as player-facing facts.
import 'recipe_book_item_info.dart';

class ReviewedRawConsumption {
  const ReviewedRawConsumption(this.name, this.effects, this.notes);
  final String name;
  final List<String> effects;
  final List<String> notes;
}

const reviewedRawConsumption = <int, ReviewedRawConsumption>{
  5401: ReviewedRawConsumption(
    "Sunrise Herb",
    ["All AP +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5402: ReviewedRawConsumption(
    "Silver Azalea",
    ["Movement Speed +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5403: ReviewedRawConsumption(
    "Fire Flake Flower",
    ["Attack Speed +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5404: ReviewedRawConsumption(
    "Dry Mane Grass",
    ["Max HP +30", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5405: ReviewedRawConsumption(
    "Silk Honey Grass",
    ["Critical Hit +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5406: ReviewedRawConsumption(
    "Everlasting Herb",
    [
      "All AP +1",
      "Movement Speed +1",
      "Attack Speed +1",
      "Max HP +30",
      "May poison you.",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5407: ReviewedRawConsumption(
    "Fortune Teller Mushroom",
    ["All Accuracy +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5408: ReviewedRawConsumption(
    "Arrow Mushroom",
    ["MP/WP/SP Recovery +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5409: ReviewedRawConsumption(
    "Dwarf Mushroom",
    ["MP/WP/SP Recovery +2", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5410: ReviewedRawConsumption(
    "Cloud Mushroom",
    ["All Evasion +2", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5411: ReviewedRawConsumption(
    "Sky Mushroom",
    ["All AP +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5412: ReviewedRawConsumption(
    "Tiger Mushroom",
    ["All Damage Reduction +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5413: ReviewedRawConsumption(
    "Emperor Mushroom",
    [
      "Knockback/Floating Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5414: ReviewedRawConsumption(
    "Ghost Mushroom",
    [
      "Knockdown/Bound Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5415: ReviewedRawConsumption(
    "Fog Mushroom",
    [
      "Knockdown/Bound Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5416: ReviewedRawConsumption(
    "Hump Mushroom",
    [
      "Stun/Stiffness/Freezing Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5417: ReviewedRawConsumption(
    "Bluffer Mushroom",
    [
      "Stun/Stiffness/Freezing Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5418: ReviewedRawConsumption(
    "Ancient Mushroom",
    [
      "Knockdown/Bound Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5419: ReviewedRawConsumption(
    "Amanita Mushroom",
    [
      "Knockdown/Bound Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5420: ReviewedRawConsumption(
    "Truffle Mushroom",
    [
      "All AP +1",
      "Movement Speed +1",
      "Attack Speed +1",
      "Max HP +30",
      "May poison you.",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5444: ReviewedRawConsumption(
    "High-quality Sunrise Herb",
    ["All AP +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5445: ReviewedRawConsumption(
    "High-quality Silver Azalea",
    ["Movement Speed +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5446: ReviewedRawConsumption(
    "High-quality Fire Flake Flower",
    ["Attack Speed +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5447: ReviewedRawConsumption(
    "High-quality Dry Mane Grass",
    ["Max HP +30", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5448: ReviewedRawConsumption(
    "High-quality Silk Honey Grass",
    ["Critical Hit +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5449: ReviewedRawConsumption(
    "High-quality Everlasting Herb",
    [
      "All AP +1",
      "Movement Speed +1",
      "Attack Speed +1",
      "Max HP +30",
      "May poison you.",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5450: ReviewedRawConsumption(
    "High-quality Fortune Teller Mushroom",
    ["All Accuracy +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5451: ReviewedRawConsumption(
    "High-quality Arrow Mushroom",
    ["MP/WP/SP Recovery +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5452: ReviewedRawConsumption(
    "High-quality Dwarf Mushroom",
    ["MP/WP/SP Recovery +2", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5453: ReviewedRawConsumption(
    "High-quality Cloud Mushroom",
    ["All Evasion +2", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5454: ReviewedRawConsumption(
    "High-quality Sky Mushroom",
    ["All AP +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5455: ReviewedRawConsumption(
    "High-quality Tiger Mushroom",
    ["All Damage Reduction +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5456: ReviewedRawConsumption(
    "High-quality Emperor Mushroom",
    [
      "Knockback/Floating Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5457: ReviewedRawConsumption(
    "High-quality Ghost Mushroom",
    [
      "Knockdown/Bound Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5459: ReviewedRawConsumption(
    "High-quality Hump Mushroom",
    [
      "Stun/Stiffness/Freezing Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5460: ReviewedRawConsumption(
    "High-quality Bluffer Mushroom",
    [
      "Stun/Stiffness/Freezing Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5461: ReviewedRawConsumption(
    "High-quality Ancient Mushroom",
    [
      "Knockdown/Bound Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5464: ReviewedRawConsumption(
    "Special Sunrise Herb",
    ["All AP +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5465: ReviewedRawConsumption(
    "Special Silver Azalea",
    ["Movement Speed +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5466: ReviewedRawConsumption(
    "Special Fire Flake Flower",
    ["Attack Speed +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5467: ReviewedRawConsumption(
    "Special Dry Mane Grass",
    ["Max HP +30", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5468: ReviewedRawConsumption(
    "Special Silk Honey Grass",
    ["Critical Hit +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5469: ReviewedRawConsumption(
    "Special Everlasting Herb",
    [
      "All AP +1",
      "Movement Speed +1",
      "Attack Speed +1",
      "Max HP +30",
      "May poison you.",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5470: ReviewedRawConsumption(
    "Special Fortune Teller Mushroom",
    ["All Accuracy +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5471: ReviewedRawConsumption(
    "Special Arrow Mushroom",
    ["MP/WP/SP Recovery +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5472: ReviewedRawConsumption(
    "Special Dwarf Mushroom",
    ["MP/WP/SP Recovery +2", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5473: ReviewedRawConsumption(
    "Special Cloud Mushroom",
    ["All Evasion +2", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5474: ReviewedRawConsumption(
    "Special Sky Mushroom",
    ["All AP +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5475: ReviewedRawConsumption(
    "Special Tiger Mushroom",
    ["All Damage Reduction +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5476: ReviewedRawConsumption(
    "Special Emperor Mushroom",
    [
      "Knockback/Floating Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5477: ReviewedRawConsumption(
    "Special Ghost Mushroom",
    [
      "Knockdown/Bound Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5478: ReviewedRawConsumption(
    "Special Fog Mushroom",
    [
      "Knockdown/Bound Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5479: ReviewedRawConsumption(
    "Special Hump Mushroom",
    [
      "Stun/Stiffness/Freezing Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5480: ReviewedRawConsumption(
    "Special Bluffer Mushroom",
    [
      "Stun/Stiffness/Freezing Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5481: ReviewedRawConsumption(
    "Special Ancient Mushroom",
    [
      "Knockdown/Bound Resistance +5%",
      "May poison you (5 damage ×3 over 9 sec).",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5544: ReviewedRawConsumption(
    "Chanterelle",
    ["Movement Speed +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5546: ReviewedRawConsumption(
    "Red-spotted Amanita",
    ["Max HP +15", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5548: ReviewedRawConsumption(
    "Mesima",
    ["HP Recovery +2", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5550: ReviewedRawConsumption(
    "Dictyophora",
    ["Critical Hit +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5552: ReviewedRawConsumption(
    "High-quality Chanterelle",
    ["Movement Speed +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5553: ReviewedRawConsumption(
    "Special Chanterelle",
    ["Movement Speed +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5554: ReviewedRawConsumption(
    "High-quality Red-spotted Amanita",
    ["Max HP +15", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5555: ReviewedRawConsumption(
    "Special Red-spotted Amanita",
    ["Max HP +15", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5556: ReviewedRawConsumption(
    "High-quality Mesima",
    ["HP Recovery +2", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5557: ReviewedRawConsumption(
    "Special Mesima",
    ["HP Recovery +2", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5558: ReviewedRawConsumption(
    "High-quality Dictyophora",
    ["Critical Hit +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  5559: ReviewedRawConsumption(
    "Special Dictyophora",
    ["Critical Hit +1", "May poison you (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7301: ReviewedRawConsumption(
    "Pepper",
    ["All AP +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7302: ReviewedRawConsumption(
    "Garlic",
    ["Movement Speed +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7303: ReviewedRawConsumption(
    "Onion",
    ["Attack Speed +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7304: ReviewedRawConsumption(
    "Strawberry",
    ["Casting Speed -1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7305: ReviewedRawConsumption(
    "Hot Pepper",
    ["Critical Hit +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7306: ReviewedRawConsumption(
    "Pumpkin",
    ["All Accuracy +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7307: ReviewedRawConsumption(
    "Grape",
    ["HP Recovery +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7308: ReviewedRawConsumption(
    "Sunflower",
    ["HP Recovery +2", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7309: ReviewedRawConsumption(
    "Olive",
    ["All Evasion +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7311: ReviewedRawConsumption(
    "Tomato",
    ["All Damage Reduction +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7312: ReviewedRawConsumption(
    "Paprika",
    ["Max HP +15", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7321: ReviewedRawConsumption(
    "High-quality Strawberry",
    ["Casting Speed -1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7322: ReviewedRawConsumption(
    "Special Strawberry",
    ["Casting Speed -1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7324: ReviewedRawConsumption(
    "High-quality Garlic",
    ["Movement Speed +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7325: ReviewedRawConsumption(
    "High-quality Onion",
    ["Attack Speed +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7327: ReviewedRawConsumption(
    "High-quality Hot Pepper",
    ["Critical Hit +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7328: ReviewedRawConsumption(
    "High-quality Pumpkin",
    ["All Accuracy +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7329: ReviewedRawConsumption(
    "High-quality Grape",
    ["HP Recovery +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7330: ReviewedRawConsumption(
    "High-quality Sunflower",
    ["HP Recovery +2", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7331: ReviewedRawConsumption(
    "High-quality Olive",
    ["All Evasion +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7333: ReviewedRawConsumption(
    "High-quality Tomato",
    ["All Damage Reduction +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7334: ReviewedRawConsumption(
    "High-quality Paprika",
    ["Max HP +15", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7335: ReviewedRawConsumption(
    "Special Pepper",
    ["All AP +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7336: ReviewedRawConsumption(
    "Special Garlic",
    ["Movement Speed +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7337: ReviewedRawConsumption(
    "Special Onion",
    ["Attack Speed +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7339: ReviewedRawConsumption(
    "Special Hot Pepper",
    ["Critical Hit +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7340: ReviewedRawConsumption(
    "Special Pumpkin",
    ["All Accuracy +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7341: ReviewedRawConsumption(
    "Special Grape",
    ["HP Recovery +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7342: ReviewedRawConsumption(
    "Special Sunflower",
    ["HP Recovery +2", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7343: ReviewedRawConsumption(
    "Special Olive",
    ["All Evasion +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7345: ReviewedRawConsumption(
    "Special Tomato",
    ["All Damage Reduction +1", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  7346: ReviewedRawConsumption(
    "Special Paprika",
    ["Max HP +15", "Also causes pain (5 damage ×3 over 9 sec)."],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
  820909: ReviewedRawConsumption(
    "White Truffle Mushroom",
    [
      "All AP +1",
      "Movement Speed +1",
      "Attack Speed +1",
      "Max HP +30",
      "May poison you.",
    ],
    ["Duration: 30 sec.", "Cooldown: 10 min."],
  ),
};

RecipeBookItemInfo withReviewedRawConsumption(
  RecipeBookItemInfo info, {
  required String? itemId,
}) {
  // Withdraw the entire metadata-only projection, not just the reported crop.
  // A mapped skill/buff and legacy tooltip text are not evidence of usability.
  return info;
}
