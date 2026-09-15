import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_crystal_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_purpose.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JIN and HAN Dawn cards retain every exact effect without filler', () {
    // Live February 5, 2026 DP-build rebalance (AP, accuracy, evasion and DR):
    // https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=12844
    // Original JIN Stamina/HP/Rage values, unchanged by that rebalance:
    // https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=7759
    // HAN secondary values remain existing data; this is not a claim that the
    // change-only February table re-verifies every unchanged statistic.
    const expected = <String, List<String>>{
      'JIN Dawn Crystal - Accuracy': <String>[
        'All AP -14',
        'All Accuracy +84',
        'Max Stamina +50',
      ],
      'HAN Dawn Crystal - Accuracy': <String>[
        'All AP -10',
        'All Accuracy +84',
        'Max Stamina +50',
      ],
      'JIN Dawn Crystal - Damage Reduction': <String>[
        'All AP -60',
        'All Damage Reduction +27',
        'Max HP +150',
      ],
      'HAN Dawn Crystal - Damage Reduction': <String>[
        'All AP -60',
        'All Damage Reduction +27',
        'Max HP +300',
      ],
      'JIN Dawn Crystal - Evasion': <String>[
        'All AP -60',
        'All Evasion +84',
        'Max HP +150',
      ],
      'HAN Dawn Crystal - Evasion': <String>[
        'All AP -60',
        'All Evasion +84',
        'Max HP +300',
      ],
      "JIN Dawn Crystal - Black Spirit's Rage": <String>[
        'All AP -6',
        "Black Spirit's Rage +25%",
      ],
      "HAN Dawn Crystal - Black Spirit's Rage": <String>[
        "Black Spirit's Rage +25%",
      ],
      'JIN Dawn Crystal - All AP': <String>['All AP +4'],
      'HAN Dawn Crystal - All AP': <String>['All AP +7'],
    };
    for (final entry in expected.entries) {
      final info = _info(entry.key);
      expect(info.effects, entry.value, reason: entry.key);
      expect(info.summary, isEmpty, reason: entry.key);
      expect(info.uses, everyElement(isNot(contains('listed'))));
    }
  });

  test('every registered crystal and Lightstone keeps its exact effects', () {
    for (final exact in exactCrystalInfoByName.values) {
      final info = _info(exact.title);
      expect(info.effects, containsAll(exact.effects), reason: exact.title);
      final lines = <String>[info.summary, ...info.uses];
      expect(lines, everyElement(isNot(contains('listed effect'))));
      expect(lines, everyElement(isNot(contains('listed stat'))));
      if (info.kind == 'Gear crystal' || info.kind == 'Lightstone') {
        expect(info.effects, isNotEmpty, reason: exact.title);
        expect(info.summary, isEmpty, reason: exact.title);
      }
    }
  });

  test('unknown effect-bearing categories never manufacture an effect', () {
    for (final kind in <String>['Gear crystal', 'Lightstone']) {
      final purpose = recipeBookItemPurposeFor(
        name: 'Unverified reference item',
        recipe: null,
        currentKind: kind,
        hasCraftUses: false,
      );
      expect(purpose.description, isEmpty);
      expect(purpose.effects, isEmpty);
      expect(purpose.uses, isEmpty);
    }
  });

  test(
    'removed Dawn Life EXP crystals label their unchanged former effects',
    () {
      const removed = <String, String>{
        'JIN Dawn Crystal - Life EXP': 'Life EXP +15%',
        'BON Dawn Crystal - Life EXP': 'Life EXP +8%',
        'WON Dawn Crystal - Life EXP': 'Life EXP +4%',
      };
      for (final entry in removed.entries) {
        final info = _info(entry.key);
        expect(info.kind, 'Legacy crystal', reason: entry.key);
        expect(info.effectsTitle, 'Former effects', reason: entry.key);
        expect(info.effects, <String>[entry.value], reason: entry.key);
        expect(
          info.summary,
          'Removed September 3, 2026; replaced with Evergreen Shards.',
          reason: entry.key,
        );
        expect(info.isTemporarilyArchived, isFalse);
        expect(info.uses, isEmpty);
      }
      final accuracy = _info('JIN Dawn Crystal - Accuracy');
      expect(accuracy.kind, 'Gear crystal');
      expect(accuracy.effectsTitle, 'Effects');
      expect(accuracy.summary, isEmpty);
    },
  );

  test('catalog effect coverage separates numeric facts from unknown gear', () {
    final snapshot = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final recipes = <String, Recipe>{};
    final names = <String, String>{};
    void addName(String name) =>
        names.putIfAbsent(name.toLowerCase(), () => name);
    for (final catalog in <ModeCatalog>[
      snapshot.alchemy,
      snapshot.cooking,
      snapshot.processing,
    ]) {
      for (final entry in catalog.items.entries) {
        recipes.putIfAbsent(entry.key.toLowerCase(), () => entry.value);
        addName(entry.key);
        for (final ingredient in <Ingredient>[
          ...entry.value.ingredients,
          for (final variant in entry.value.variants) ...variant.ingredients,
        ]) {
          addName(ingredient.name);
          ingredient.options.forEach(addName);
          ingredient.substituteRatios.keys.forEach(addName);
        }
      }
    }
    final counts = <String, int>{};
    final noEffects = <String, List<String>>{};
    final effectItems = <String, List<String>>{};
    for (final entry in names.entries) {
      final info = _info(entry.value, recipe: recipes[entry.key]);
      counts.update(info.kind, (value) => value + 1, ifAbsent: () => 1);
      if (info.effects.isEmpty) {
        noEffects.putIfAbsent(info.kind, () => <String>[]).add(entry.value);
      } else {
        effectItems[entry.value] = info.effects;
      }
      expect(
        <String>[info.summary, ...info.uses],
        everyElement(isNot(contains('listed stat effect'))),
        reason: entry.value,
      );
      expect(info.summary, isNot(contains('for its listed effect')));
      if (info.kind == 'Gear crystal' || info.kind == 'Lightstone') {
        expect(info.effects, isNotEmpty, reason: entry.value);
      }
    }
    // Opt-in external evidence only: normal tests never write into the source
    // tree or the user's profile, and this audit performs no network calls.
    final evidence = Platform.environment['ITEM_EFFECTS_AUDIT_JSON'];
    if (evidence != null && evidence.isNotEmpty) {
      File(evidence).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object>{
          'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
          'uniqueCatalogNames': names.length,
          'exactCrystalRegistryEntries': exactCrystalInfoByName.length,
          'withEffects': effectItems.length,
          'kinds': counts,
          'noEffectsByKind': noEffects,
          'effectsByName': effectItems,
          'scope':
              'Catalog outputs, ingredients, variants, options and substitutes; '
              'presence audit, not a fresh verification of every game statistic.',
        }),
      );
    }
  });
}

RecipeBookItemInfo _info(String name, {Recipe? recipe}) => recipeBookInfoFor(
  name: name,
  recipe: recipe,
  searchTerms: const <String>[],
  consumerRecipes: const <Recipe>[],
)!;
