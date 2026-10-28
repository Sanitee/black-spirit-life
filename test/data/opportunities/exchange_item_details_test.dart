import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_item_details.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exchange item facts cover Supreme tools and current fishing chair', () {
    expect(
      exchangeItemDetails[3743]!.effects,
      containsAll(['Cooking Time −1 sec', 'Durability: 5,000']),
    );
    expect(
      exchangeItemDetails[3744]!.effects,
      containsAll(['Alchemy Time −1 sec', 'Durability: 5,000']),
    );
    final chair = exchangeItemDetails[12930]!;
    expect(chair.kind, 'Fishing chair');
    expect(
      chair.notes,
      contains('Expires 7 days after being obtained from its box.'),
    );
    expect(
      chair.effects,
      isEmpty,
      reason: 'Do not carry forward obsolete durability or unverified bonuses.',
    );
  });

  test('exchange item facts preserve Royal Workshop buff distinctions', () {
    final expected = {
      821137: 'Combat EXP +500%',
      821139: 'Item Drop Rate +50%',
      821141: 'Life EXP +150%',
      821143: 'Life Skill Mastery +300',
      821145: 'Energy Recovery +25',
    };
    for (final entry in expected.entries) {
      final info = exchangeItemDetails[entry.key]!;
      expect(info.kind, 'Consumable');
      expect(info.effects, hasLength(2));
      expect(info.effects, contains(entry.value));
      expect(
        info.notes,
        containsAll(['Duration: 3 hours.', 'Cooldown: 3 hours.']),
      );
      expect(info.notes.last, startsWith('Cannot be used together with '));
    }
  });

  test('Morning Light tools identify their actual use and reduction', () {
    for (final entry in {3749: 'Cooking', 3750: 'Alchemy'}.entries) {
      final info = exchangeItemDetails[entry.key]!;
      expect(info.kind, isNot('Recipe material'));
      expect(
        info.effects,
        containsAll(['${entry.value} Time −1 sec', 'Durability: 3,000']),
      );
      expect(info.howToObtain, hasLength(2));
      expect(info.notes.single, contains('${entry.value} Repair Tool'));
    }
  });

  test('material references do not claim the finished item buffs', () {
    for (final id in [820139, 820140, 820141, 820143, 820893, 820035, 820036]) {
      expect(exchangeItemDetails[id]!.summary, isNotEmpty);
      expect(exchangeItemDetails[id]!.effects, isEmpty, reason: 'Item $id');
    }
  });

  test('food ingredient fallback formulas are exact and display-only', () {
    final rice = exchangeItemDetails[820140]!.recipes.single;
    expect(rice.output, 'Miraculous Tteokguk');
    expect(rice.method, 'Simple Cooking');
    expect(rice.ingredients, {
      'Strange and Beautiful Rice': 50,
      'Garaetteok': 1,
      'Pork': 1,
      'Egg': 1,
      'Mineral Water': 1,
    });
    final meat = exchangeItemDetails[820139]!.recipes.single;
    expect(meat.output, 'Miraculous Nourishing Soup');
    expect(meat.ingredients, {
      'Live Meat': 1,
      'Jujube': 5,
      'Youngji Mushroom': 5,
      'Tiger Meat': 5,
      'Mineral Water': 2,
    });
  });

  test('fragments have their own equipped stats and upgrade use', () {
    for (final id in [15729, 15731, 15734]) {
      final info = exchangeItemDetails[id]!;
      expect(info.kind, 'Crystal');
      expect(info.effects, isNotEmpty);
      expect(info.uses.single, contains('Simple Alchemy'));
    }
    expect(
      exchangeItemDetails[15734]!.effects,
      contains('Extra AP Against Monsters +10'),
    );
    expect(exchangeItemDetails[15731]!.effects, contains('All Evasion +15'));
  });
}
