// NA/EU Guaranteed PEN Boss Gear guide + exact current PC item descriptions.
// See docs/reviewed-reform-recycling.json. Deliberately informational: recycling
// consumes an unused multi-output stone and must not become a planning cycle.
import 'recipe_book_item_info.dart';

class ReviewedReformSource {
  const ReviewedReformSource(this.name, this.stones);
  final String name;
  final String stones;
  String get text => 'Grinding · Recycle unused $stones';
}

const reviewedReformMaterialSources = <int, ReviewedReformSource>{
  4470: ReviewedReformSource(
    'Black Crystal',
    'Resplendent Boss Weapon Reform Stone IV',
  ),
  4483: ReviewedReformSource(
    'Blue Crystal',
    'Resplendent Boss Weapon Reform Stone II',
  ),
  8904: ReviewedReformSource(
    'Concentrated Boss Crystal',
    'Resplendent Boss Reform Stones',
  ),
  16004: ReviewedReformSource(
    'Concentrated Magical Black Stone',
    'Resplendent Boss Reform Stones',
  ),
  8917: ReviewedReformSource(
    'Contained Boss Aura',
    'Resplendent Boss Reform Stones V',
  ),
  4469: ReviewedReformSource(
    'Green Crystal',
    'Resplendent Boss Weapon Reform Stone I',
  ),
  4918: ReviewedReformSource(
    'Magical Shard',
    'Resplendent Boss Reform Stones I–IV',
  ),
  44195: ReviewedReformSource(
    'Memory Fragment',
    'Resplendent Boss Reform Stones',
  ),
  8903: ReviewedReformSource(
    'Oquilla Earth Crystal',
    'Resplendent Boss Armor Reform Stone V',
  ),
  8902: ReviewedReformSource(
    'Oquilla Sky Crystal',
    'Resplendent Boss Weapon Reform Stone V',
  ),
  4468: ReviewedReformSource(
    'Red Crystal',
    'Resplendent Boss Weapon Reform Stone III',
  ),
  4405: ReviewedReformSource(
    'Rough Diamond',
    'Resplendent Boss Armor Reform Stone IV',
  ),
  4404: ReviewedReformSource(
    'Rough Emerald',
    'Resplendent Boss Armor Reform Stone I',
  ),
  4401: ReviewedReformSource(
    'Rough Ruby',
    'Resplendent Boss Armor Reform Stone III',
  ),
  4402: ReviewedReformSource(
    'Rough Sapphire',
    'Resplendent Boss Armor Reform Stone II',
  ),
};

const reviewedRecyclableReformStones = <int, String>{
  8801: 'Resplendent Boss Weapon Reform Stone I',
  8802: 'Resplendent Boss Weapon Reform Stone II',
  8803: 'Resplendent Boss Weapon Reform Stone III',
  8804: 'Resplendent Boss Weapon Reform Stone IV',
  8805: 'Resplendent Boss Weapon Reform Stone V',
  8826: 'Resplendent Boss Armor Reform Stone I',
  8827: 'Resplendent Boss Armor Reform Stone II',
  8828: 'Resplendent Boss Armor Reform Stone III',
  8829: 'Resplendent Boss Armor Reform Stone IV',
  8830: 'Resplendent Boss Armor Reform Stone V',
};

const reviewedReformRecyclingNote =
    'Grinding returns its crafting materials (destroys the unused stone).';

RecipeBookItemInfo withReviewedReformRecycling(
  RecipeBookItemInfo info, {
  required String? itemId,
}) {
  if (info.isTemporarilyArchived) return info;
  final id = int.tryParse(itemId ?? '');
  final source = reviewedReformMaterialSources[id];
  final name = info.title.trim().toLowerCase();
  if (source != null && source.name.toLowerCase() == name) {
    return info.copyWith(
      acquisitionNotes: {...info.acquisitionNotes, source.text}.toList(),
    );
  }
  final stone = reviewedRecyclableReformStones[id];
  if (stone == null || stone.toLowerCase() != name) return info;
  return info.copyWith(
    notes: {...info.notes, reviewedReformRecyclingNote}.toList(),
  );
}
