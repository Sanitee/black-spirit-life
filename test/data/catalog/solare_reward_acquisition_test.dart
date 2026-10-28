import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  late Map<String, dynamic> raw;
  late PlannerApplicationController application;
  late RecipeBookController book;

  setUpAll(() {
    final text = File('assets/data/app-data.json').readAsStringSync();
    raw = jsonDecode(text) as Map<String, dynamic>;
    catalog = const BundledCatalogParser().parse(text);
  });
  setUp(() {
    ModeState state(CraftMode mode, String target) => ModeState(
      target: target,
      want: 1,
      bonusTarget: target,
      market: MarketState(),
      appearance: AppearanceSettings.defaultsFor(mode),
    );
    application = PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'solare-reference-test',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 10, 15),
        activeMode: CraftMode.processing,
        alchemy: state(CraftMode.alchemy, 'Clear Liquid Reagent'),
        cooking: state(CraftMode.cooking, 'Beer'),
        processing: state(CraftMode.processing, 'Wheat Flour'),
        processingYields: const {},
        marketTax: MarketTax(),
        showDeleteTools: false,
      ),
      saveState: (value) async => value,
      saveDebounce: Duration.zero,
    );
    book = RecipeBookController(
      modeController: application.active,
      catalogRepository: CatalogRepository(catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: application.active.craftableNames,
    );
  });
  tearDown(() async {
    book.dispose();
    await application.dispose();
  });

  for (final (name, itemId, quantity) in const [
    ('Sturdy Forest Tread', 820022, 20),
    ('Perfume of Envy', 1411, 30),
    ('Perfume of Tenacity', 1413, 30),
  ]) {
    test('$name has the exact rank-limited reward in every item-info mode', () {
      final rule = application.active.resolveItemAcquisition(name)!;
      expect(rule.itemId, itemId);
      expect(rule.reviewedAt, '2026-10-15');
      final reward = rule.routes.singleWhere((r) => r.kind == 'season_reward');
      expect(reward.availability, 'season-rank-limited');
      expect(reward.summary, contains('Receive $quantity from'));
      expect(reward.summary, contains('ranked season in the Top 100'));
      for (final mode in CraftMode.values) {
        final info = book.itemInfoFor(name, mode: mode)!;
        expect(info.acquisitionNotes, contains(reward.summary));
        expect(
          info.acquisitionFormulas.where(
            (formula) => formula.method.contains('Solare'),
          ),
          isEmpty,
        );
        if (name.startsWith('Perfume')) {
          expect(info.effects, isNotEmpty);
          expect(info.acquisitionFormulas, isNotEmpty);
        }
      }
      final acquisition = raw['acquisitionInfo'] as Map<String, dynamic>;
      final entry = acquisition[name] as Map<String, dynamic>;
      final route = (entry['routes'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((r) => r['kind'] == 'season_reward');
      expect(
        (route['sources'] as List<dynamic>).cast<Map<String, dynamic>>().map(
          (s) => s['url'],
        ),
        containsAll([
          'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10699',
          'https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=19924',
        ]),
      );
    });
  }

  test('existing Sturdy Forest Tread sources are retained', () {
    final summaries = application.active
        .resolveItemAcquisition('Sturdy Forest Tread')!
        .displayableSummaries;
    expect(summaries, hasLength(3));
    expect(summaries.join(' '), contains("Manshaum Narc's Stone"));
    expect(summaries.join(' '), contains('Peridot Petal ×50'));
  });

  test('perfume rewards do not become bulk crafting outputs', () {
    for (final name in ['Perfume of Envy', 'Perfume of Tenacity']) {
      final recipe = catalog.processing.items[name]!;
      expect(recipe.outputMinimum, 1);
      expect(recipe.outputMaximum, 1);
      expect(recipe.variants, hasLength(2));
      expect(recipe.variants.map((v) => v.batchMultiplier), [1, 10]);
      expect(recipe.ingredients.map((i) => i.quantity), [1, 3, 10]);
      expect(
        recipe.ingredients.first.name,
        name.endsWith('Envy') ? 'Perfume of Courage' : 'Perfume of Deep Sea',
      );
    }
    for (final name in ['Perfume of Courage', 'Perfume of Deep Sea']) {
      final rule = application.active.resolveItemAcquisition(name);
      expect(
        rule?.displayableSummaries.join(' ') ?? '',
        isNot(contains('Glorious Solare Box')),
      );
    }
  });

  test('review metadata excludes events and preserves extraction date', () {
    final review = raw['weeklyPatchReview'] as Map<String, dynamic>;
    final followUp = (review['followUpReviews'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .last;
    expect(followUp['reviewedAt'], '2026-10-15');
    expect(followUp['scope'], contains('Event content is excluded'));
    final clientEvidence = review['clientEvidence'] as Map<String, dynamic>;
    expect(clientEvidence['clientDate'], '2026-09-03');
    expect(
      (followUp['unresolved'] as List<dynamic>).join(' '),
      contains('distance calculations are unchanged'),
    );
  });
}
