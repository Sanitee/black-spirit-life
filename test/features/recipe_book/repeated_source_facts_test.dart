import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> compact(String title, List<String> sources) =>
    withReadableRecipeBookSections(
      RecipeBookItemInfo(
        title: title,
        kind: 'Item',
        summary: '',
        acquisitionNotes: sources,
      ),
    ).acquisitionNotes;

void main() {
  final morningLightSources = <String, String>{
    'Primordial Crystal': 'Morning Light World Boss subjugation rewards.',
    'Embers of the Primordial':
        'Obtain Embers of the Primordial from Morning Light World Boss subjugation rewards.',
    for (final suffix in [
      'All AP',
      'All Accuracy',
      'All Damage Reduction',
      'All Evasion',
      'Max HP',
      'Critical Hit Rate',
      'Back Attack Extra Damage',
      'Down Attack Extra Damage',
      'Air Attack Extra Damage',
      'Critical Hit Extra Damage',
      "Black Spirit's Rage Recovery",
    ])
      'Reforge Stone - $suffix':
          'Obtain Reforge Stone - $suffix from eligible Land of the Morning Light World Boss rewards, or buy it through the Central Market.',
  };
  for (final entry in morningLightSources.entries) {
    test('Morning Light duplicate source compaction: ${entry.key}', () {
      const short = 'World bosses · Morning Light';
      const separate = 'Exchange · 1 token → 1 material · Up to 4 per week';
      for (final source in [
        [entry.value, short, separate],
        [short, entry.value, separate],
      ]) {
        expect(compact(entry.key, source), [entry.value, separate]);
        expect(compact(entry.key, compact(entry.key, source)), [
          entry.value,
          separate,
        ]);
      }
      expect(compact(entry.key, [short]), [short]);
      expect(compact('Other item', [entry.value, short]), [entry.value, short]);
      const qualified = '$short (special event only)';
      expect(compact(entry.key, [entry.value, qualified]), [
        entry.value,
        qualified,
      ]);
      final changed = entry.value.replaceFirst('World Boss', 'Guild Boss');
      expect(compact(entry.key, [changed, short]), [changed, short]);
    });
  }
  const short = "Exchange · 10 Witch's Delicacy → 120 Milk with Liana";
  const full =
      "Exchange · 10 Witch's Delicacy → 120 Milk · Liana · major cities; Nadia Rowen · Olvia";
  test(
    'complete exchange replaces duplicate regardless of order; remains idempotent',
    () {
      for (final sources in [
        [short, full],
        [full, short],
      ]) {
        expect(compact('Milk', sources), [full]);
        expect(compact('Milk', compact('Milk', sources)), [full]);
      }
      expect(compact('Milk', [short]), [short]);
    },
  );
  for (final other in [
    full.replaceFirst('10 Witch', '20 Witch'),
    full.replaceFirst('120 Milk', '100 Milk'),
    full.replaceFirst('Liana ·', 'Dalishain ·'),
    full.replaceFirst("Witch's Delicacy", 'Fairy’s Breath'),
    full.replaceFirst('120 Milk', '120 Beer'),
    'Exchange · 10 Witch\'s Delicacy → 120 Milk · Liana elsewhere',
  ]) {
    test('different exchange is retained: $other', () {
      expect(compact('Milk', [short, other]), [short, other]);
    });
  }
  test('extra restriction on short line cannot be discarded', () {
    const restricted = '$short (weekly quest only)';
    expect(compact('Milk', [restricted, full]), [restricted, full]);
    const limited = '$full · Up to 1 per week';
    expect(compact('Milk', [short, limited]), [limited]);
  });
  test(
    'separate locations remain separate and output containers are preserved',
    () {
      const another =
          "Exchange · 10 Witch's Delicacy → 120 Milk · Bofin · Olvia";
      expect(compact('Milk', [short, full, another]), [full, another]);
      const box =
          "Exchange · 10 Witch's Delicacy → 120 Milk (from Box) · Liana · major cities";
      expect(compact('Milk', [short, box]), [short, box]);
    },
  );
  test(
    'exact reviewed pair preserves the complete non-gathering restriction',
    () {
      const old = "Defeat Naga Marsh's Poisonous Plants.";
      const full =
          'Defeat Poisonous Swamp Plants in Naga Marsh or Glish Swamp; do not try to gather this drop with a tool.';
      for (final part in ['Flower', 'Leaf', 'Stalk']) {
        expect(compact('Insectivore Plant $part', [old, full]), [full]);
        expect(compact('Insectivore Plant $part', [old]), [old]);
      }
      expect(compact('Other item', [old, full]), [old, full]);
      expect(compact('Insectivore Plant Flower', ['$old Rare drop.', full]), [
        '$old Rare drop.',
        full,
      ]);
    },
  );
  test('mixed-source line keeps the separate Hunter Seal alternative', () {
    const mixed =
        "In Manage Currency, exchange 1 Dark Spirit's Greed or 5 Hunter's Seals for 10 Masses of Pure Magic.";
    const single =
        "Exchange · 1 Dark Spirit's Greed → 10 Mass of Pure Magic · Manage Currency";
    expect(compact('Mass of Pure Magic', [mixed, single]), [mixed]);
    expect(compact('Mass of Pure Magic', [single]), [single]);
    expect(compact('Mass of Pure Magic', [mixed, '$single · Event only']), [
      mixed,
      '$single · Event only',
    ]);
  });
}
