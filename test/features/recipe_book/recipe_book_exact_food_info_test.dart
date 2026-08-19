import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_food_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'registry covers every effect-bearing cooking result in the catalog',
    () {
      final snapshot = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      const cookingIntermediates = <String>{
        'vinegar',
        'essence of liquor',
        'white sauce',
        'red sauce',
        'dressing',
        'citron vinegar',
        'single-brewed mesima tea',
        'twice-brewed mesima tea',
      };
      const simpleCookingIntermediates = <String>{
        'diluted grain wine',
        'grape-scented herbal wine',
        'refined grain wine',
      };
      final expected = <String>{
        for (final entry in snapshot.cooking.items.entries)
          if ((entry.value.type == 'cooking' &&
                  !cookingIntermediates.contains(_fold(entry.key))) ||
              (entry.value.qualityBase != null &&
                  (entry.value.group == 'Cooking' ||
                      entry.value.group == 'Meals')) ||
              (entry.value.type == 'gathered' &&
                  entry.value.group == 'Cooking'))
            _fold(entry.key),
        for (final entry in snapshot.processing.items.entries)
          if (entry.value.method == 'Simple Cooking' &&
              !simpleCookingIntermediates.contains(_fold(entry.key)))
            _fold(entry.key),
      };

      expect(expected, hasLength(278));
      expect(
        exactFoodInfoByName.keys.toSet().difference(expected),
        isEmpty,
        reason:
            'The registry contains names that are not reachable catalog items.',
      );
      expect(
        expected.difference(exactFoodInfoByName.keys.toSet()),
        isEmpty,
        reason:
            'An effect-bearing cooking result has no exact consumable info.',
      );
    },
  );

  test('copy is concise, factual, and structurally complete', () {
    const bannedFragments = <String>[
      'how to obtain',
      'ingredients:',
      'usage effect',
      'bdo codex',
      'etc.',
      'shows here because',
      'imported from',
    ];
    final failures = <String>[];

    for (final entry in exactFoodInfoByName.entries) {
      final info = entry.value;
      if (entry.key != _fold(entry.key) ||
          info.title.trim().isEmpty ||
          info.kind.trim().isEmpty ||
          info.description.trim().isEmpty ||
          info.effects.isEmpty) {
        failures.add('${entry.key}: incomplete fields');
        continue;
      }
      if (info.description.length > 140) {
        failures.add('${entry.key}: description is too long');
      }
      if (info.effects.any(
        (effect) =>
            effect.trim().isEmpty ||
            effect.length > 90 ||
            effect != effect.trim(),
      )) {
        failures.add('${entry.key}: malformed effect');
      }
      final text = <String>[
        info.description,
        ...info.effects,
      ].join(' ').toLowerCase();
      for (final fragment in bannedFragments) {
        if (text.contains(fragment)) {
          failures.add('${entry.key}: contains "$fragment"');
        }
      }
      final normalizedEffects = info.effects.map(_semantic).toSet();
      if (normalizedEffects.length != info.effects.length) {
        failures.add('${entry.key}: duplicate effect');
      }
    }

    expect(failures, isEmpty);
  });

  test('nonstandard consumables retain their exact observable effects', () {
    expect(exactFoodInfoByName['beer']?.effects, <String>[
      'Recover 2 Worker Stamina',
    ]);
    expect(exactFoodInfoByName['carrot confit']?.effects, <String>[
      'Recover 12,500 Mount Stamina',
      'Recover 5,500 Mount HP',
    ]);
    expect(exactFoodInfoByName['organic feed']?.effects, <String>[
      'Recover 140 Hunger',
    ]);
    expect(exactFoodInfoByName['chowder']?.effects, <String>[
      'Recover 100 Sailor Condition',
    ]);
    expect(exactFoodInfoByName['citron tea']?.effects, <String>[
      'Cures Frostbite',
    ]);
    expect(exactFoodInfoByName['well-brewed mesima tea']?.effects, <String>[
      'Immune to Frostbite',
    ]);
    expect(exactFoodInfoByName['star anise tea']?.effects, <String>[
      'Cures Hypothermia',
    ]);
    expect(exactFoodInfoByName['byeot county gukbap']?.effects, <String>[
      'Immediate Health EXP (up to Health Lv. 40)',
    ]);
    expect(exactFoodInfoByName['moodle gukbap']?.effects, <String>[
      'Immediate Breath EXP (up to Breath Lv. 40)',
    ]);
    expect(exactFoodInfoByName['dalbeol gukbap']?.effects, <String>[
      'Immediate Strength EXP (up to Strength Lv. 40)',
    ]);
  });

  test(
    'higher-grade cooking results keep item-specific effects and timers',
    () {
      final balenos = exactFoodInfoByName['special balenos meal'];
      expect(balenos?.kind, 'Meal');
      expect(balenos?.effects, <String>[
        'Movement Speed +2',
        'Fishing Speed +2',
        'Gathering Speed +2',
      ]);
      expect(balenos?.duration, '120 min');
      expect(balenos?.cooldown, '30 min');

      final beer = exactFoodInfoByName['cold draft beer'];
      expect(beer?.kind, 'Worker recovery food');
      expect(beer?.effects, <String>['Recover 3 Worker Stamina']);
      expect(beer?.duration, isEmpty);
      expect(beer?.cooldown, isEmpty);

      final coconut = exactFoodInfoByName['sweet coconut pasta'];
      expect(coconut?.effects, <String>[
        'Heatstroke/Hypothermia Resistance +10% (Max +90%)',
      ]);
      expect(coconut?.duration, '90 min');
      expect(coconut?.cooldown, '30 min');

      expect(exactFoodInfoByName['thick fruit juice']?.effects, <String>[
        'Max MP/WP/SP +30',
      ]);
      expect(exactFoodInfoByName['chilled delotia juice']?.effects, <String>[
        'Extra AP Against Monsters +5',
      ]);
      expect(exactFoodInfoByName['sweet citron juice']?.effects, <String>[
        'Fishing Speed +1',
      ]);
    },
  );

  test('Cron Meals keep their current effects and short cooldown', () {
    final seafood = exactFoodInfoByName['seafood cron meal'];
    expect(
      seafood?.effects,
      containsAll(<String>[
        'Alchemy/Cooking Time -0.6 sec',
        'Life EXP +10%',
        'Life Skill Mastery +25',
      ]),
    );
    expect(seafood?.duration, '120 min');
    expect(seafood?.cooldown, '10 sec');

    final simple = exactFoodInfoByName['simple cron meal'];
    expect(
      simple?.effects,
      containsAll(<String>[
        'Extra AP Against Monsters +30',
        'Combat EXP +20%',
        'Monster Damage Reduction Rate +6%',
      ]),
    );
    expect(simple?.duration, '120 min');
    expect(simple?.cooldown, '10 sec');

    final exquisite = exactFoodInfoByName['exquisite cron meal'];
    expect(
      exquisite?.effects,
      containsAll(<String>[
        'All AP +8',
        'Max HP +525',
        'Critical Hit Extra Damage +5%',
      ]),
    );
    expect(exquisite?.duration, '120 min');
    expect(exquisite?.cooldown, '10 sec');
  });

  test('timed food and meal records have duration and cooldown values', () {
    final failures = <String>[];
    for (final entry in exactFoodInfoByName.entries) {
      final info = entry.value;
      if ((info.kind == 'Food' || info.kind == 'Meal') &&
          (info.duration.isEmpty || info.cooldown.isEmpty)) {
        failures.add(entry.key);
      }
    }
    expect(failures, isEmpty);
  });
}

String _fold(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _semantic(String value) =>
    _fold(value).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
