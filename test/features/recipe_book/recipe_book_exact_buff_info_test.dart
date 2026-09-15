import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_buff_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every supported draught changed by the August patch lasts 20 minutes',
    () {
      for (final name in const <String>[
        "beast's draught",
        "giant's draught",
        'savage draught',
        'frenzy draught',
        'armor draught',
        'elixir of indignation',
        'viridian draught',
        'frenzy draught of corruption',
        'immortal: frenzy draught of corruption',
        "immortal: beast's draught",
        "immortal: giant's draught",
        'immortal: savage draught',
        'immortal: frenzy draught',
        'immortal: elixir of indignation',
        'immortal: armor draught',
        'fury draught',
        'immortal: fury draught',
        'adaptation draught',
        'immortal: adaptation draught',
        'potential draught',
        'immortal: potential draught',
        'corruption draught',
        'immortal: corruption draught',
        'berserk draught',
        'immortal: berserk draught',
        'harmony draught',
        'immortal: harmony draught',
        'harmony draught - human',
        'harmony draught - demihuman',
        'harmony draught - kamasylvia',
        'harmony draught - edania',
      ]) {
        expect(exactBuffInfoByName[name]?.duration, '20 min', reason: name);
      }
    },
  );

  test('current draught effects and durations match the August review', () {
    expect(exactBuffInfoByName['adaptation draught']?.duration, '20 min');
    expect(exactBuffInfoByName['berserk draught']?.effects, <String>[
      'All Special Attack Extra Damage +16%',
    ]);
    expect(exactBuffInfoByName['corruption draught']?.duration, '20 min');
    expect(exactBuffInfoByName['fury draught']?.effects, <String>[
      'All AP +13',
      'All Accuracy +13',
      'All Special Attack Extra Damage +2%',
    ]);
    expect(exactBuffInfoByName['potential draught']?.duration, '20 min');
  });

  test('Great Ocean draughts keep their exact effects and timers', () {
    final ocean = exactBuffInfoByName['ocean draught'];
    expect(ocean?.effects, <String>[
      'Sailing EXP +20%',
      'Barter EXP +20%',
      'Sailor EXP +10%',
    ]);
    expect(ocean?.duration, '180 min');

    expect(exactBuffInfoByName['vast ocean draught']?.duration, '360 min');
    final endless = exactBuffInfoByName['endless ocean draught'];
    expect(endless?.effects, <String>[
      'Sailing EXP +25%',
      'Barter EXP +25%',
      'Sailor EXP +15%',
      'Sailing Mastery +50',
    ]);
    expect(endless?.duration, '600 min');
    expect(endless?.cooldown, '10 sec');
  });
}
