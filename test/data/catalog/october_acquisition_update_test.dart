import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/acquisition_notes.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/item_acquisition_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  late PlannerRules rules;
  late Map<String, Object?> raw;

  setUpAll(() {
    final source = File('assets/data/app-data.json').readAsStringSync();
    raw = jsonDecode(source) as Map<String, Object?>;
    catalog = const BundledCatalogParser().parse(source);
    rules = const PlannerAssembly().plannerRules(catalog.supportingData);
  });

  ItemAcquisitionRule guidance(String name) =>
      resolveItemAcquisition(name: name, rules: rules)!;

  for (final type in ['Sky', 'Earth']) {
    final name = 'Oquilla $type Crystal';
    test('$name distinguishes retired starts from accepted quests', () {
      final rule = guidance(name);
      expect(rule.reviewedAt, '2026-10-06');
      expect(rule.routes.single.availability, 'restricted');
      final copy = rule.displayableSummaries.single;
      expect(copy, contains('$name I quest can no longer be accepted'));
      expect(copy, contains('23 September 2026'));
      expect(copy, contains('Already accepted quests can still be completed'));
      expect(copy, contains('required by your accepted quest'));
      expect(copy, contains('Old Moon Manager'));

      // The same reviewed copy must reach Planner notes and the item popup.
      final notes = composeAcquisitionNotes(notes: rule.displayableSummaries);
      final info = withResearchedAcquisition(
        recipeBookInfoFor(
          name: name,
          recipe: catalog.processing.items[name],
          searchTerms: const [],
          consumerRecipes: const [],
        )!,
        rule.displayableSummaries,
      );
      expect(notes.join(' '), contains('Already accepted quests'));
      expect(info.acquisitionNotes.join(' '), contains('can no longer'));
      expect(info.acquisitionNotes.join(' '), contains('still be completed'));
      final entry = _object(_object(raw['acquisitionInfo'])[name]);
      final route = _object((entry['routes']! as List<Object?>).single);
      final sources = (route['sources']! as List<Object?>).map(_object);
      expect(sources.any((s) => '${s['url']}'.contains('10621')), isTrue);
    });
  }

  test('quest retirement does not remove valid reform-stone processing', () {
    for (final entry in [('Armor', 'Earth'), ('Weapon', 'Sky')]) {
      final recipe = catalog
          .processing
          .items['Resplendent Boss ${entry.$1} Reform Stone V']!;
      expect(recipe.isCraftable, isTrue);
      expect(recipe.method, 'Heating');
      expect(recipe.outputMinimum, 1);
      expect(recipe.outputMaximum, 1);
      expect(recipe.ingredients.first.name, 'Oquilla ${entry.$2} Crystal');
      expect(recipe.ingredients.first.quantity, 1);
      expect(
        catalog
            .processing
            .items['Oquilla ${entry.$2} Crystal']!
            .isReferenceOnly,
        isTrue,
      );
    }
  });

  test(
    'Twilight weekly paths retain gates, ordered costs and shared limit',
    () {
      for (final type in ['Necklace', 'Earring', 'Ring', 'Belt']) {
        final rule = guidance('Twilight of the End - $type');
        final route = rule.routes.singleWhere(
          (r) => r.availability == 'weekly',
        );
        expect(route.kind, 'quest_exchange');
        expect(route.summary, contains('[Weekly] For the Throne'));
        expect(route.summary, contains('[Weekly] One Who Defies the End'));
        expect(route.summary, contains('quests I-X in order'));
        expect(route.summary, contains('x10 each for I-V; x30 each for VI-X'));
        expect(route.summary, contains('Up to 10 rewards per week'));
        expect(route.summary, contains('not 10 per throne'));
        expect(route.summary, contains('Only one weekly throne'));
        expect(rule.routes.first.summary, contains('Central Market'));
        final lowerThrone = type == 'Necklace' ? 'Magaia' : 'Aphrodon';
        if (type != 'Earring') {
          expect(route.summary, isNot(contains(lowerThrone)));
        }
      }
    },
  );

  test('only Earring and Ring claim the limited Tier 4 Agris route', () {
    for (final type in ['Necklace', 'Earring', 'Ring', 'Belt']) {
      final routes = guidance(
        'Twilight of the End - $type',
      ).routes.where((r) => r.kind == 'currency_exchange');
      if (type == 'Earring' || type == 'Ring') {
        final route = routes.single;
        expect(route.availability, 'family-limited');
        expect(route.summary, contains('50 coins for 1'));
        expect(route.summary, contains('Tier 4 must be unlocked'));
        expect(route.summary, contains('10 exchanges per Family at this tier'));
      } else {
        expect(routes, isEmpty);
      }
    }
  });

  test(
    'follow-up review does not claim a new client extraction or map fix',
    () {
      final review = _object(raw['weeklyPatchReview']);
      expect(_object(review['clientEvidence'])['clientDate'], '2026-09-03');
      final followUp = _object(
        (review['followUpReviews']! as List<Object?>).singleWhere(
          (entry) => _object(entry)['reviewedAt'] == '2026-10-06',
        ),
      );
      expect(followUp['reviewedAt'], '2026-10-06');
      expect(
        (followUp['unresolved']! as List<Object?>).join(' '),
        contains('No map or distance edits'),
      );
    },
  );

  test('Coral Crystal lists Khan in shared acquisition guidance', () {
    final rule = guidance('Coral Crystal');
    expect(rule.reviewedAt, '2026-10-09');
    expect(rule.routes.single.availability, 'permanent');
    expect(rule.displayableSummaries.single, contains('including Khan'));
    expect(
      composeAcquisitionNotes(notes: rule.displayableSummaries).join(' '),
      contains('including Khan'),
    );
    final entry = _object(_object(raw['acquisitionInfo'])['Coral Crystal']);
    final route = _object((entry['routes']! as List<Object?>).single);
    expect(
      (route['sources']! as List<Object?>)
          .map(_object)
          .any((source) => '${source['url']}'.contains('10678')),
      isTrue,
    );
  });

  test(
    'October 8 follow-up excludes events and unverified fishing origins',
    () {
      final review = _object(raw['weeklyPatchReview']);
      final followUp = _object(
        (review['followUpReviews']! as List<Object?>).singleWhere(
          (entry) => _object(entry)['reviewedAt'] == '2026-10-09',
        ),
      );
      expect(followUp['reviewedAt'], '2026-10-09');
      expect('${followUp['scope']}', contains('Event content is excluded'));
      expect(
        (followUp['unresolved']! as List<Object?>).join(' '),
        contains('Fishing origins and distance calculations are unchanged'),
      );
      expect(_object(review['clientEvidence'])['clientDate'], '2026-09-03');
    },
  );
}

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;
