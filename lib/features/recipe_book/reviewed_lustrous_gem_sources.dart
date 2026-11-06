// Exact current PC rewards and July 17, 2025 no-NPC opening change.
// See docs/reviewed-lustrous-gem-sources.json. No automatic opening or EV model.
import 'recipe_book_item_info.dart';

const reviewedLustrousGemRewards = <int, (String, String, bool)>{
  15628: ('Black Magic Crystal - Harphia', '1', false),
  15629: ('Black Magic Crystal - Cobelinus', '1', false),
  15630: ('Black Magic Crystal - Viper', '1', false),
  15631: ('Black Magic Crystal - Hystria', '1', false),
  15632: ('Black Magic Crystal - Carmae', '1', false),
  15650: ('Black Magic Crystal - Addis', '1', false),
  5862: ('Scorched Fragment', '1–2', false),
  4403: ('Rough Topaz', '2–4', false),
  4402: ('Rough Sapphire', '2–4', false),
  4404: ('Rough Emerald', '2–4', false),
  4401: ('Rough Ruby', '2–4', false),
  4405: ('Rough Diamond', '2–4', false),
  4006: ('Rough Stone', '7–13', true),
  4901: ('Black Stone Powder', '7–13', true),
  5169: ('Sturdy Snow White Stone', '1–2', false),
};

RecipeBookItemInfo withReviewedLustrousGemSources(
  RecipeBookItemInfo info, {
  required String? itemId,
}) {
  final id = int.tryParse(itemId ?? '');
  final reward = reviewedLustrousGemRewards[id];
  if (reward == null ||
      info.isTemporarilyArchived ||
      info.title.trim().toLowerCase() != reward.$1.toLowerCase()) {
    return info;
  }
  const oldPowderSources = {
    'Grind Black Stone for the normal high-yield recipe, or buy Black Stone Powder through the Central Market.',
    'Grind a Black Stone or eligible Magic Crystal, craft it at a Refinery, or buy it from the Central Market.',
  };
  final chance = reward.$3 ? '' : ' (chance)';
  return info.copyWith(
    acquisitionNotes: {
      ...info.acquisitionNotes.where(
        (s) => id != 4901 || !oldPowderSources.contains(s),
      ),
      if (id == 4901) ...[
        'Grinding · Black Stone or eligible Magic Crystals',
        'Workers · Refinery',
        'Central Market',
      ],
      'Rough Lustrous Gem · Open for ${reward.$2}$chance; found in Starlight Veins',
    }.toList(),
  );
}
