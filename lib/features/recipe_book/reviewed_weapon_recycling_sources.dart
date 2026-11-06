// PC publisher-supported weapon sources, corroborated by current exact inputs.
// Evidence, historical rates and exclusions: reviewed-weapon-recycling-sources.json.
// Informational only: never consumes equipment in the planner or invents yields.
import 'recipe_book_item_info.dart';

const reviewedWeaponRecyclingSources = <int, (String, List<String>)>{
  4053: (
    'Pure Iron Crystal',
    ['Heating · Kalis Florang (chance; consumes the weapon)'],
  ),
  4056: (
    'Pure Lead Crystal',
    ['Heating · Seleth Florang (chance; consumes the weapon)'],
  ),
  4259: (
    'Pure Platinum Crystal',
    ['Heating · Bares Florang (chance; consumes the weapon)'],
  ),
  4253: (
    'Pure Silver Crystal',
    ['Heating · Krea Florang (chance; consumes the weapon)'],
  ),
  4062: (
    'Pure Tin Crystal',
    ['Heating · Ain Florang (chance; consumes the weapon)'],
  ),
  4083: (
    'Pure Titanium Crystal',
    ['Heating · Rosar Florang (chance; consumes the weapon)'],
  ),
  4065: (
    'Pure Zinc Crystal',
    ['Heating · Yuria Florang (chance; consumes the weapon)'],
  ),
  5960: (
    'Trace of Nature',
    ['Heating · Certain main weapons, e.g. Ain Florang (consumes the weapon)'],
  ),
};

RecipeBookItemInfo withReviewedWeaponRecyclingSources(
  RecipeBookItemInfo info, {
  required String? itemId,
}) {
  final fact = reviewedWeaponRecyclingSources[int.tryParse(itemId ?? '')];
  if (fact == null ||
      info.isTemporarilyArchived ||
      info.title.trim().toLowerCase() != fact.$1.toLowerCase()) {
    return info;
  }
  final sources = {...info.acquisitionNotes};
  final notes = {...info.notes};
  // This is a planner limitation, not an acquisition method. Match only this
  // exact legacy sentence; never discard other restrictions or source details.
  if (sources.remove(
    'Curated to the standard ingot + metal solvent route; gear-melting variants are intentionally excluded from the planner.',
  )) {
    notes.add('Planner uses the ingot + Metal Solvent recipe.');
  }
  return info.copyWith(
    acquisitionNotes: {...sources, ...fact.$2}.toList(),
    notes: notes.toList(),
  );
}
