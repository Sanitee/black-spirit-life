// Exact PC guide / patch-supported source hints. No automatic loot or quest EV.
// Evidence and exclusions: docs/reviewed-monster-quest-sources.json.
import 'recipe_book_item_info.dart';

const reviewedMonsterQuestSources = <int, (String, List<String>)>{
  // Current keyed PC Monster Zone Info; see reviewed-zone-source-hints.json.
  // No numerical drop rate or Dehkia-version assumption.
  11816: (
    'Blue Coral Earring',
    ['Monster drops · Pirate Island or Padix Island'],
  ),
  11817: (
    'Red Coral Earring',
    ['Monster drops · Pirate Island or Padix Island'],
  ),
  12017: ('Blue Coral Ring', ['Monster drops · Pirate Island']),
  12018: ('Red Coral Ring', ['Monster drops · Pirate Island']),
  11807: ('Token of Friendship', ['Monster drops · Cyclops Land']),
  // Exact PC source and later-change screen: reviewed-padix-taritas-sources.json.
  11856: ('Ethereal Earring', ['Monster drops · Padix Island']),
  12091: ('Ocean Haze Ring', ['Monster drops · Padix Island']),
  12208: ('Rhutum Elite Belt', ['Monster drops · Rhutum Outstation']),
  11808: ("Witch's Earring", ['Monster drops · Hexe Sanctuary']),
  12210: (
    'Tree Spirit Belt',
    ['Monster drops · Mutant Tree Spirits, North Kaia Mountain'],
  ),
  11853: ('Black Distortion Earring', ["Monster drops · Star's End"]),
  11855: (
    'Dawn Earring',
    ['Monster drops · Abandoned Monastery (Restricted Territory)'],
  ),
  12007: (
    'Mark of Shadow',
    [
      'World boss · Nightmarish Kzarka (server top 50; deal at least 0.01% of boss HP)',
    ],
  ),
  12008: (
    'Shrine Guardian Token',
    [
      'World boss · Nightmarish Kzarka (server top 50; deal at least 0.01% of boss HP)',
    ],
  ),
  11811: ('Ridell Earring', ['Monster drops · Abandoned Iron Mine']),
  12211: (
    'Belt of Shultz the Gladiator',
    ['Monster drops · Wandering Rogue Den, Manes Hideout or Shultz Guard'],
  ),
  11631: (
    'Necklace of Shultz the Gladiator',
    ['Monster drops · Wandering Rogue Den, Manes Hideout or Shultz Guard'],
  ),
  11613: ("Ancient Guardian's Seal", ['Monster drops · Helms Post']),
  11610: ('Scarla Necklace', ['Monster drops · Helms Post']),
  12012: ("Outlaw's Ring", ['Monster drops · Elric Shrine']),
  11810: ('Mesto Earring', ["Monster drops · Soldier's Cemetery"]),
  12220: ('Ancient Weapon Core', ['Monster drops · Hasrah Ancient Ruins']),
  11630: ("Laytenn's Power Stone", ['Monster drops · Kratuga Ancient Ruins']),
  11828: (
    'Tungrad Earring',
    ['Monster drops · Aakman Temple or Kratuga Ancient Ruins'],
  ),
  11629: (
    'Tungrad Necklace',
    ['Monster drops · Hystria Ruins or Gyfin Rhasia Temple (Underground)'],
  ),
  12060: ('Eye of the Ruins Ring', ['Monster drops · Tshira Ruins']),
  12059: ('Kagtum Submission Ring', ['Monster drops · Blood Wolf Settlement']),
  12251: ("Orkinrad's Belt", ['Monster drops · Sherekhan Necropolis']),
  12045: ('Rainbow Coral Ring', ['Monster drops · Protty Cave']),
  12061: ('Tungrad Ring', ['Monster drops · Sycraia Ruins (Upper or Lower)']),
  12068: ('Ominous Ring', ['Monster drops · Thornwood Forest']),
  44461: ('Turo Heart', ['Monster drops · Tunkuta']),
  12257: ("Turo's Belt", ['Monster drops · Tunkuta']),
  44335: (
    "Vell's Concentrated Magic",
    ['World boss · Vell (chance from rewards)'],
  ),
  11834: ('Narc Ear Accessory', ['Monster drops · Manshaum Forest']),
  12236: ('Valtarra Eclipsed Belt', ['Monster drops · Mirumok Ruins']),
  12042: (
    'Forest Ronaros Ring',
    ['Monster drops · Forest Ronaros, Tooth Fairy Forest'],
  ),
  12237: ('Tungrad Belt', ['Monster drops · Gyfin Rhasia Temple']),
  11653: ('Deboreka Necklace', ['Monster drops · Ash Forest']),
  43786: ('Remnants of the Rift', ['Dark Rift bosses · Chance from rewards']),
  44304: ('Wind Spirit Stone Fragment', ['Main quests · Kamasylvia']),
  44305: ('Earth Spirit Stone Fragment', ['Main quests · Kamasylvia']),
  44306: ('Water Spirit Stone Fragment', ['Main quests · Kamasylvia']),
  44311: (
    'Tree Spirit Stone Fragment',
    ['Main quests · Kamasylvia', 'World boss · Mirumok Destroyer Offin'],
  ),
};

RecipeBookItemInfo withReviewedMonsterQuestSources(
  RecipeBookItemInfo info, {
  required String? itemId,
}) {
  final id = int.tryParse(itemId ?? '');
  final fact = reviewedMonsterQuestSources[id];
  if (fact == null ||
      info.isTemporarilyArchived ||
      info.title.trim().toLowerCase() != fact.$1.toLowerCase()) {
    return info;
  }
  final sources = {...info.acquisitionNotes};
  // These two exact lines describe the same source, not separate drop routes.
  if (const {44304, 44305, 44306, 44311}.contains(id) &&
      sources.contains('Monster drops · Kamasylvia')) {
    sources.remove('Defeat monsters in Kamasylvia.');
  }
  return info.copyWith(acquisitionNotes: {...sources, ...fact.$2}.toList());
}
