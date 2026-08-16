import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_crystal_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact crystal copy stays compact and free of scraped fragments', () {
    const bannedFragments = <String>[
      'etc.',
      'craft the following items',
      'crafting materials:',
      'usage #',
      'self-obtainable',
      'processing (l)',
      'gear- slumbering',
      'itemsessence',
      'materialsprimordial',
    ];
    final failures = <String>[];

    for (final entry in exactCrystalInfoByName.entries) {
      final info = entry.value;
      final lines = <String>[...info.effects, ...info.uses];

      if (entry.key != entry.key.toLowerCase() ||
          info.title.trim().isEmpty ||
          lines.any((line) => line != line.trim() || line.length > 120)) {
        failures.add(entry.key);
        continue;
      }

      for (final line in lines) {
        final folded = line.toLowerCase();
        if (bannedFragments.any(folded.contains)) {
          failures.add('${entry.key}: $line');
        }
      }
    }

    expect(failures, isEmpty);
  });

  test('effect and purpose lines do not repeat within an item', () {
    final failures = <String>[];

    for (final entry in exactCrystalInfoByName.entries) {
      for (final section in <List<String>>[
        entry.value.effects,
        entry.value.uses,
      ]) {
        final normalized = section.map(_normalize).toList(growable: false);
        if (normalized.toSet().length != normalized.length) {
          failures.add(entry.key);
        }
      }
    }

    expect(failures, isEmpty);
  });

  test('lightstones remain a distinct effect-bearing family', () {
    final amplified = exactCrystalInfoByName.entries
        .where((entry) => entry.key.startsWith('amplified lightstone of '))
        .toList(growable: false);

    expect(amplified, isNotEmpty);
    for (final entry in amplified) {
      expect(entry.value.title, contains('Lightstone'));
      expect(entry.value.effects, isNotEmpty);
      expect(
        entry.value.uses,
        contains(
          'Hand over unwanted Lightstone x3 to Dalishain located in major cities and towns to receive Purified Lightstone x1.',
        ),
      );
    }

    for (final entry in exactCrystalInfoByName.entries.where(
      (entry) => entry.key.contains('lightstone'),
    )) {
      expect(entry.value.title, contains('Lightstone'));
    }
  });

  test(
    'Sea Crystal containers label possible rewards rather than item effects',
    () {
      for (final name in <String>[
        'eltro crystal',
        'margoria crystal',
        'rusalka crystal',
        'serni crystal',
      ]) {
        final info = exactCrystalInfoByName[name];
        expect(info?.kind, 'Sea Crystal container', reason: name);
        expect(info?.effectsTitle, 'Possible Sea Crystal Stats', reason: name);
        expect(info?.effects, isNotEmpty, reason: name);
        expect(
          info?.uses.single,
          startsWith('Open it to receive'),
          reason: name,
        );
      }
    },
  );

  test('rolled Sea Crystals are ship equipment, not crystal-preset items', () {
    for (final name in <String>[
      'eltro sea crystal',
      'margoria sea crystal',
      'rusalka sea crystal',
      'serni sea crystal',
    ]) {
      final info = exactCrystalInfoByName[name];
      expect(info?.kind, 'Ship crystal', reason: name);
      expect(info?.effects, isEmpty, reason: name);
      expect(info?.uses.first, startsWith('Install it on'), reason: name);
    }
  });

  test('cleaned high-impact families retain concrete information', () {
    expect(
      exactCrystalInfoByName['bon crystal of dusky ruin']?.effects,
      <String>[
        'Extra AP Against Edanian Monsters +30',
        'Monster Damage Reduction +10',
      ],
    );
    expect(
      exactCrystalInfoByName['flawless herald\'s crystal']?.uses,
      contains(
        'Reforms Kabua\'s Artifact or a Dehkia\'s Artifact into its Heralding version.',
      ),
    );
    expect(
      exactCrystalInfoByName['distorted crystal of origin']?.uses.first,
      contains('Distorted Slumbering Origin defense gear to Silent'),
    );
    expect(
      exactCrystalInfoByName['silent crystal of origin']?.uses.first,
      contains('Silent Slumbering Origin defense gear to Wailing'),
    );
    expect(
      exactCrystalInfoByName['primordial glow crystal']?.uses.single,
      contains('Extra AP Against Monsters +10'),
    );
    expect(
      exactCrystalInfoByName['sunset glow crystal']?.uses,
      contains('Heat with 1 Forest Fury to recover 10,000 Caphras Stones.'),
    );
  });

  test('recipe acquisition text is not mislabeled as a crystal effect', () {
    for (final entry in exactCrystalInfoByName.entries) {
      expect(
        entry.value.effects.where(
          (effect) =>
              effect.toLowerCase().startsWith('craft ') ||
              effect.toLowerCase().startsWith('heat ') ||
              effect.toLowerCase().startsWith('obtain ') ||
              effect.toLowerCase().startsWith('or craft '),
        ),
        isEmpty,
        reason: entry.key,
      );
    }

    expect(
      exactCrystalInfoByName['awakened spirit\'s crystal']?.effects,
      <String>['Max HP +150', 'All AP +5'],
    );
    expect(
      exactCrystalInfoByName['han dawn crystal - accuracy']?.uses.single,
      startsWith('Heat to recover'),
    );
  });
}

String _normalize(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
