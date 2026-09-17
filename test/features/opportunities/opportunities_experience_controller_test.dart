import 'dart:convert';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_effort.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'numeric EXP sorts both ways with all unknown rows at the end',
    () async {
      final f = await _Fixture.create(CraftMode.alchemy);
      addTearDown(f.dispose);
      final c = f.controller;
      c.selectCraftSort('exp');
      await c.calculationSettled;
      final descending = c.visibleQuotes;
      expect(descending.any((q) => c.experienceForQuote(q) != null), isTrue);
      expect(descending.any((q) => c.experienceForQuote(q) == null), isTrue);
      expect(
        descending.any((q) => c.experienceForQuote(q)?.estimated == true),
        isTrue,
      );
      _expectNumericOrder(c, descending, ascending: false);
      c.reverseCraftSort('exp');
      await c.calculationSettled;
      _expectNumericOrder(c, c.visibleQuotes, ascending: true);
      expect(
        c.visibleQuotes.map((q) => q.recipeName).toSet(),
        descending.map((q) => q.recipeName).toSet(),
      );
    },
  );

  test(
    'unknown filtering is exclusive to EXP and survives other sorts',
    () async {
      final f = await _Fixture.create(CraftMode.alchemy);
      addTearDown(f.dispose);
      final c = f.controller;
      final all = c.visibleQuotes.map((q) => q.recipeName).toSet();
      c.setUnknownExpFilter('hide');
      final known = c.visibleQuotes.map((q) => q.recipeName).toSet();
      expect(known, isNotEmpty);
      expect(
        c.visibleQuotes.every((q) => c.experienceForQuote(q) != null),
        isTrue,
      );
      c.setUnknownExpFilter('only');
      final unknown = c.visibleQuotes.map((q) => q.recipeName).toSet();
      expect(unknown, isNotEmpty);
      expect(
        c.visibleQuotes.every((q) => c.experienceForQuote(q) == null),
        isTrue,
      );
      expect(known.intersection(unknown), isEmpty);
      expect({...known, ...unknown}, all);
      for (final sort in ['profit', 'preorders']) {
        c.selectCraftSort(sort);
        expect(c.preferences.unknownExpFilter, 'only');
        expect(c.visibleQuotes.map((q) => q.recipeName).toSet(), all);
      }
      c.selectCraftSort('exp');
      expect(c.visibleQuotes.map((q) => q.recipeName).toSet(), unknown);
      c.setUnknownExpFilter('include');
      expect(c.visibleQuotes.map((q) => q.recipeName).toSet(), all);
    },
  );

  test('unknown effort reverses without reversing alphabetical ties', () async {
    final f = await _Fixture.create(CraftMode.processing);
    addTearDown(f.dispose);
    final c = f.controller;
    c.setUnknownExpFilter('only');
    final index = RecipeEffortIndex(
      {
        for (final mode in CraftMode.values)
          mode: f.harness.bundle.controller.modes[mode]!.recipes,
      },
      legacyUnavailableItems:
          f.harness.bundle.controller.plannerRules.legacyUnavailableItems,
    );
    RecipeEffort effort(OpportunityQuote q) => index.effortFor(
      c.recipes[q.recipeName]!.resolveVariant(q.selectedVariantId),
      CraftMode.processing,
    );
    final descending = c.visibleQuotes;
    expect(descending.length, greaterThan(100));
    expect(
      effort(descending.first).compareTo(effort(descending.last)),
      greaterThan(0),
    );
    _expectEffortOrder(descending, effort, ascending: false);
    c.reverseCraftSort('exp');
    final ascending = c.visibleQuotes;
    _expectEffortOrder(ascending, effort, ascending: true);
    expect(effort(ascending.first), effort(descending.last));
    expect(effort(ascending.last), effort(descending.first));
    expect(
      ascending.map((q) => q.recipeName).toSet(),
      descending.map((q) => q.recipeName).toSet(),
    );
  });

  test('ordinary sorts reverse values but leave missing values last', () async {
    final f = await _Fixture.create(CraftMode.cooking);
    addTearDown(f.dispose);
    final c = f.controller;
    c.quotes = [
      _quote('High', profit: 50, demand: 70),
      _quote('Missing'),
      _quote('Low', profit: 10, demand: 2),
    ];
    for (final sort in ['profit', 'preorders']) {
      c.preferences.craftSort = sort;
      expect(c.visibleQuotes.map((q) => q.recipeName), [
        'High',
        'Low',
        'Missing',
      ]);
      c.preferences.craftSortAscending[sort] = true;
      expect(c.visibleQuotes.map((q) => q.recipeName), [
        'Low',
        'High',
        'Missing',
      ]);
    }
  });

  test(
    'new controls save only Opportunities preferences and keep direction per sort',
    () async {
      final f = await _Fixture.create(CraftMode.processing);
      addTearDown(f.dispose);
      final c = f.controller;
      final before = f.harness.bundle.controller.documentSnapshot;
      c.selectCraftSort('exp');
      expect(c.preferences.craftAscending, isFalse);
      c.selectCraftSort('exp');
      expect(c.preferences.craftAscending, isFalse);
      c.reverseCraftSort('exp');
      c.setUnknownExpFilter('only');
      c.selectCraftSort('profit');
      expect(c.preferences.craftAscending, isFalse);
      c.selectCraftSort('profit', toggleDirection: true);
      expect(c.preferences.craftAscending, isTrue);
      c.selectCraftSort('exp');
      expect(c.preferences.craftAscending, isTrue);
      final prefsBefore = jsonEncode(c.preferences.toJson());
      c.selectCraftSort('invalid');
      c.reverseCraftSort('invalid');
      c.setUnknownExpFilter('invalid');
      expect(jsonEncode(c.preferences.toJson()), prefsBefore);
      await c.flush();
      final saved = await OpportunitiesPreferenceStore(
        f.harness.temporaryDirectory,
      ).load();
      expect(saved.unknownExpFilter, 'only');
      expect(saved.craftSortAscending['exp'], isTrue);
      expect(saved.craftSortAscending['profit'], isTrue);
      expect(f.harness.bundle.controller.documentSnapshot, same(before));
    },
  );
}

void _expectNumericOrder(
  OpportunitiesController c,
  List<OpportunityQuote> rows, {
  required bool ascending,
}) {
  double? previous;
  var reachedUnknown = false;
  for (final row in rows) {
    final xp = c.experienceForQuote(row);
    if (xp == null) {
      reachedUnknown = true;
    } else {
      expect(reachedUnknown, isFalse);
      if (previous != null) {
        expect(
          xp.value,
          ascending
              ? greaterThanOrEqualTo(previous)
              : lessThanOrEqualTo(previous),
        );
      }
      previous = xp.value;
    }
  }
}

void _expectEffortOrder(
  List<OpportunityQuote> rows,
  RecipeEffort Function(OpportunityQuote) effort, {
  required bool ascending,
}) {
  for (var i = 1; i < rows.length; i++) {
    final comparison = effort(rows[i - 1]).compareTo(effort(rows[i]));
    expect(
      comparison,
      ascending ? lessThanOrEqualTo(0) : greaterThanOrEqualTo(0),
      reason: '${rows[i - 1].recipeName} / ${rows[i].recipeName}',
    );
    if (comparison == 0) {
      expect(
        rows[i - 1].recipeName.compareTo(rows[i].recipeName),
        lessThanOrEqualTo(0),
      );
    }
  }
}

final class _Fixture {
  _Fixture(this.harness, this.controller);
  final ApplicationTestHarness harness;
  final OpportunitiesController controller;
  static Future<_Fixture> create(CraftMode mode) async {
    final harness = await ApplicationTestHarness.create();
    final controller = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: CatalogRepository(harness.bundle.catalog),
      directory: harness.temporaryDirectory,
      clock: () => DateTime.utc(2026, 9, 17),
      serviceFactory: (_) =>
          throw StateError('No network allowed in EXP tests.'),
    );
    await controller.ready;
    controller.change((p) {
      p.mode = mode;
      p.profitableOnly = false;
    }, assemble: true);
    await controller.calculationSettled;
    return _Fixture(harness, controller);
  }

  Future<void> dispose() async {
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

OpportunityQuote _quote(String name, {double? profit, int? demand}) =>
    OpportunityQuote(
      recipeName: name,
      selectedVariantId: null,
      variantLabel: null,
      batchMultiplier: 1,
      crafts: 1,
      outputPerCraft: 1,
      expectedOutput: 1,
      outputMarket: demand == null
          ? null
          : OpportunityMarketItem(
              itemId: '90001',
              asks: const [],
              bids: [OpportunityMarketLevel(price: 100, quantity: demand)],
              bookFetchedAt: DateTime.utc(2026, 9, 17),
            ),
      ingredients: const [],
      listingRevenue: profit,
      inputCost: 0,
      preliminaryInputCost: 0,
      buyerRevenue: profit,
      buyerFilledQuantity: 1,
      marketReady: true,
      buyersCoverOutput: true,
      inputCapacityKnown: false,
      inputCraftCapacity: null,
      buyerCraftCapacity: null,
      estimatedSeconds: null,
      issues: const [],
    );
