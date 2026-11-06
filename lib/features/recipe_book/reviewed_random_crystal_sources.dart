// Publisher PC release notes + explicit current PC descriptions.
// See docs/reviewed-random-crystal-sources.json. Never infer equal odds.
import 'recipe_book_item_info.dart';

const reviewedRandomCrystalTypes = <String>[
  'Harphia',
  'Cobelinus',
  'Viper',
  'Hystria',
  'Carmae',
  'Addis',
];
const reviewedRandomCrystalGrades = <String>['JIN', 'BON', 'WON'];
const reviewedRandomCrystalResult =
    'Result · 1 matching JIN, BON or WON crystal (random)';
const reviewedRandomCrystalUsage =
    'Simple Alchemy · Craft a random JIN, BON or WON crystal.';
const reviewedRandomCrystalInputs = <int, String>{
  4917: 'Forest Fury',
  4918: 'Magical Shard',
  15628: 'Black Magic Crystal - Harphia',
  15629: 'Black Magic Crystal - Cobelinus',
  15630: 'Black Magic Crystal - Viper',
  15631: 'Black Magic Crystal - Hystria',
  15632: 'Black Magic Crystal - Carmae',
  15650: 'Black Magic Crystal - Addis',
};

RecipeBookItemInfo withReviewedRandomCrystalSources(
  RecipeBookItemInfo info, {
  required String? itemId,
}) {
  final id = int.tryParse(itemId ?? '');
  if (id == null || info.isTemporarilyArchived) {
    return info;
  }
  final input = reviewedRandomCrystalInputs[id];
  if (input != null && info.title.trim().toLowerCase() == input.toLowerCase()) {
    return info.copyWith(
      uses: {
        ...info.uses.where(
          (line) =>
              line !=
              'Combine with crystals and Magical Shards through Simple Alchemy.',
        ),
        reviewedRandomCrystalUsage,
      }.toList(),
    );
  }
  if (id < 15801 || id > 15818) {
    return info;
  }
  final offset = id - 15801;
  final type = reviewedRandomCrystalTypes[offset ~/ 3];
  final grade = reviewedRandomCrystalGrades[offset % 3];
  if (info.title.trim().toLowerCase() !=
      '$grade Magic Crystal - $type'.toLowerCase()) {
    return info;
  }
  const superseded = <String>{
    'Simple Alchemy · Random result (recipe in Crafting Notes)',
    'Use Simple Alchemy with the recipe shown in Crafting Notes; the result is chance-based.',
  };
  return info.copyWith(
    acquisitionNotes: {
      ...info.acquisitionNotes.where((line) => !superseded.contains(line)),
      'Simple Alchemy · Black Magic Crystal - $type ×1 + Forest Fury ×1 + Magical Shard ×10',
      reviewedRandomCrystalResult,
    }.toList(),
  );
}
